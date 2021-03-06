Red/System []

#enum json-type! [
    JSON_NULL: 1
    JSON_FALSE: 2
    JSON_TRUE: 3
    JSON_NUMBER: 4
    JSON_STRING: 5
    JSON_ARRAY: 6
    JSON_OBJECT: 7
]

#enum json-parse-result! [
    PARSE_OK: 1
    PARSE_EXPECT_VALUE: 2
    PARSE_INVALID_VALUE: 3
    PARSE_ROOT_NOT_SINGULAR: 4
    PARSE_NUMBER_TOO_BIG: 5
    PARSE_MISS_QUOTATION_MARK: 6
    PARSE_INVALID_STRING_ESCAPE: 7
    PARSE_MISS_COMMA_OR_SQUARE_BRACKET: 8
    PARSE_MISS_KEY: 9
    PARSE_MISS_COLON: 10
    PARSE_MISS_COMMA_OR_CURLY_BRACKET: 11
]

#define KEY_NOT_EXIST -1

;- Note: Red/System 不支持 union 联合体，
;-       所以只能在结果体里冗余 number/string/array 几种情况
json-value!: alias struct! [    ;- 用于承载解析后的结果
    type    [json-type!]        ;- 类型，见 json-type!
    num     [float!]            ;- 数值
    str     [c-string!]         ;- 字符串
    arr     [json-value!]       ;- 指向 json-value! 的数组，嵌套了自身类型的指针
    objs    [byte-ptr!]         ;- 指向 json-member! 即 JSON 对象的数组的地址
    len     [integer!]          ;- 字符串长度 or 数组元素个数
]

json-member!: alias struct! [
    key     [c-string!]         ;- key
    klen    [integer!]          ;- key 的字符个数
    val     [json-value! value] ;- 值，支持嵌套整个，而不是引用
]


json: context [
    _ctx: declare struct! [         ;- 用于承载解析过程的中间数据
        json    [c-string!]         ;- JSON 字符串
        stack   [byte-ptr!]         ;- 动态数组，按字节存储
        size    [integer!]          ;- 当前栈大小，按 byte 计
        top     [integer!]          ;- 可 push/pop 任意大小
    ]

    parse-whitespace: func [/local s][
        s: _ctx/json
        while [any [s/1 = space s/1 = tab s/1 = cr s/1 = lf]][
            s: s + 1
        ]
        _ctx/json: s
    ]

    expect: func [char [byte!]][
        assert _ctx/json/1 = char
        _ctx/json: _ctx/json + 1
    ]

    parse-null: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  s
    ][
        expect #"n"

        s: _ctx/json
        if any [s/1 <> #"u" s/2 <> #"l" s/3 <> #"l" ][
            return PARSE_INVALID_VALUE
        ]

        _ctx/json: _ctx/json + 3
        v/type: JSON_NULL
        PARSE_OK
    ]

    parse-true: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  s
    ][
        expect #"t"

        s: _ctx/json
        if any [s/1 <> #"r" s/2 <> #"u" s/3 <> #"e"][
            return PARSE_INVALID_VALUE
        ]

        _ctx/json: _ctx/json + 3
        v/type: JSON_TRUE
        PARSE_OK
    ]

    parse-false: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  s
    ][
        expect #"f"

        s: _ctx/json
        if any [s/1 <> #"a" s/2 <> #"l" s/3 <> #"s" s/4 <> #"e" ][
            return PARSE_INVALID_VALUE
        ]

        _ctx/json: _ctx/json + 4
        v/type: JSON_FALSE
        PARSE_OK
    ]

    #define ISDIGIT(v)      [all [v >= #"0" v <= #"9"]]
    #define ISDIGIT1TO9(v)  [all [v >= #"1" v <= #"9"]]
    #define JUMP_TO_NOT_DIGIT [
        until [
            s: s + 1
            not ISDIGIT(s/1)    ;- 不是数字则跳出
        ]
    ]

    parse-number: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  s
    ][
        s: _ctx/json

        ;- 校验格式
        if s/1 = #"-" [s: s + 1]

        either s/1 = #"0" [s: s + 1][
            ;- 不是 0 开头，接下来必须是 1~9，否则报错
            if not ISDIGIT1TO9(s/1) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        if s/1 = #"." [
            s: s + 1
            if not ISDIGIT(s/1) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        if any [s/1 = #"e" s/1 = #"E"][
            s: s + 1
            if any [s/1 = #"+" s/1 = #"-"][s: s + 1]
            if not ISDIGIT(s/1) [return PARSE_INVALID_VALUE]
            JUMP_TO_NOT_DIGIT
        ]

        ;- TODO: 不知道怎么实现数字过大时要用 errno 判断 ERANGE、HUGE_VAL 几个宏的问题
        ;- SEE https://zh.cppreference.com/w/c/string/byte/strtof
        v/num: strtod as byte-ptr! _ctx/json null
        if null? s [return PARSE_INVALID_VALUE]

        _ctx/json: s    ;- 跳到成功转型后的下一个字节
        v/type: JSON_NUMBER
        PARSE_OK
    ]

    ;------------- stack functions ----------------

    #define PARSE_STACK_INIT_SIZE 256   ;- 初始的栈大小
    #import [
        LIBC-file cdecl [
            realloc:    "realloc" [
                ptr     [byte-ptr!]
                size    [integer!]
                return: [byte-ptr!]
            ]
        ]
    ]

    ;- 解析过程中入栈，其实是在栈中申请指定的 size 个 byte!，
    ;- 然后调用方把值写入这个申请到的空间，例如：
    ;-      1. string 的每一个字符
    ;-      2. 数组或对象的每一个元素（json-value! 结构）
    context-push: func [
        size    [integer!]
        return: [byte-ptr!]             ;- 返回可用的起始地址
        /local  ret
    ][
        assert size > 0

        ;- 栈空间不足
        if _ctx/top + size >= _ctx/size [
            if _ctx/size = 0 [_ctx/size: PARSE_STACK_INIT_SIZE]     ;- 首次初始化

            while [_ctx/top + size >= _ctx/size][
                _ctx/size: _ctx/size + (_ctx/size >> 1)    ;- 每次加 2倍
            ]
            _ctx/stack: realloc _ctx/stack _ctx/size       ;- 重新分配内存
        ]

        ret: _ctx/stack + _ctx/top        ;- 返回数据起始的指针
        _ctx/top: _ctx/top + size         ;- 指向新的栈顶
        ret
    ]
    
    #define PUTC(ch) [
        top: context-push 1
        top/value: ch
    ]

    ;- pop 返回 byte-ptr!，由调用者根据情况补上末尾的 null 来形成 c-string!，
    ;- 因为栈不是只给 string 使用的，数组、对象都要用到
    context-pop: func [
        size    [integer!]
        return: [byte-ptr!]
        /local  ret
    ][
        assert _ctx/top >= size
        _ctx/top: _ctx/top - size         ;- 更新栈顶指针
        ret: _ctx/stack + _ctx/top        ;- 返回缩减后的栈顶指针：栈基地址 + 偏移

        ;- Note: 如果 json 是空字符串，这里返回的是地址 0，小心
        ;printf ["context-pop ret: %d^/" ret]
        ret
    ]

    ;------------- parsing functions ----------------
    make-string: func [
        bytes   [byte-ptr!]
        len     [integer!]
        return: [c-string!]
        /local  target end
    ][
        target: allocate len + 1
        copy-memory target bytes len
        end: target + len
        end/value: null-byte        ;- 补上终结符
        ;printf ["make-string '%s' address: %d^/" (as-c-string target) target]
        as-c-string target
    ]

    bytes-ptr!: alias struct! [     ;- 字符串数组
        bytes [byte-ptr!]
    ]

    parse-string-raw: func [
        "解析 JSON 字符串，把结果写入 bytes 指针和 len 指针"
        bytes-ptr   [bytes-ptr!]
        len-ptr     [int-ptr!]
        return:     [integer!]
        /local      head len p ch top ret
    ][
        head: _ctx/top          ;- 记录字符串起始点，即开头的 "
        expect #"^""            ;- 字符串必定以双引号开头，跳到下一个字符

        p: _ctx/json
        forever [
            ch: p/1
            p: p + 1            ;- 先指向下一个字符
            switch ch [
                #"^"" [         ;- 字符串结束符
                    len: _ctx/top - head
                    ;printf ["parse-string-raw finish with len: %d^/" len]
                    ;- 取出栈中的字节流，空字符串可能会返回 0
                    bytes-ptr/bytes: context-pop len
                    len-ptr/value: len
                    _ctx/json: p

                    return PARSE_OK
                ]
                #"\" [
                    ch: p/1
                    p: p + 1
                    switch ch [
                        #"^""   [PUTC(#"^"")]
                        #"\"    [PUTC(#"\")]
                        #"/"    [PUTC(#"/")]
                        #"n"    [PUTC(#"^M")]
                        #"r"    [PUTC(#"^/")]
                        #"t"    [PUTC(#"^-")]
                        ;- TODO 这几个转义符不知道在 R/S 里怎么对应
                        ;#"b"    [PUTC(#"\b")]
                        ;#"f"    [PUTC(#"\f")]
                        default [
                            _ctx/top: head
                            return PARSE_INVALID_STRING_ESCAPE
                        ]
                    ]
                ]
                null-byte [
                    _ctx/top: head
                    return PARSE_MISS_QUOTATION_MARK    ;- 没有用 " 结尾
                ]
                default [
                    ;- TODO 非法字符
                    PUTC(ch)
                ]
            ]
        ]
        0
    ]

    parse-string: func [
        v       [json-value!]
        return: [integer!]
        /local
            bytes-ptr   [bytes-ptr!]
            len-ptr     [int-ptr!]
            ret         [integer!]
    ][
        bytes-ptr: declare bytes-ptr!
        bytes-ptr/bytes: declare byte-ptr!
        len-ptr: declare int-ptr!

        ret: parse-string-raw bytes-ptr len-ptr
        if ret = PARSE_OK [
            set-string v bytes-ptr/bytes len-ptr/value
        ]

        ret
    ]

    parse-array: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local  e ret size target i
    ][
        expect #"["
        parse-whitespace                            ;- 第一个元素前可能有空白符
        if _ctx/json/1 = #"]" [
            _ctx/json: _ctx/json + 1
            v/type: JSON_ARRAY
            v/len: 0
            v/arr: null                             ;- 空数组
            return PARSE_OK
        ]

        size: 0
        e: declare json-value!                      ;- 承载数组的元素
        forever [
            init-value e
            parse-whitespace                        ;- 每个元素前可能有空白符

            ret: parse-value e                      ;- 解析元素，并用新的 json-value! 来承载
            if ret <> PARSE_OK [break]              ;- 解析元素失败，跳出 while 释放内存

            ;- 解析元素成功
            ;- 把 json-value! 结构入栈（其实是申请空间，返回可用的起始地址），
            ;- 用解析得到的元素来填充栈空间，释放掉这个临时 json-value! 结构
            target: context-push size? json-value!
            copy-memory target (as byte-ptr! e) (size? json-value!)
            size: size + 1
            parse-whitespace                        ;- 每个元素结束后可能有空白符

            switch _ctx/json/1 [
                #"," [
                    _ctx/json: _ctx/json + 1      ;- 跳过数组内的逗号
                ]
                #"]" [
                    _ctx/json: _ctx/json + 1      ;- 数组结束，从栈中复制到 json-value!
                    v/type: JSON_ARRAY
                    v/len: size

                    size: size * size? json-value!
                    target: allocate size       ;- 注意，这里用 malloc 分配内存
                    copy-memory target (context-pop size) size

                    v/arr: as json-value! target;- 这里其实是 json-value! 数组

                    return PARSE_OK
                ]
                default [
                    ;- 异常，元素后面既不是逗号，也不是方括号来结束
                    ;- 先保存解析结果，跳出 while 之后清理栈中已分配的内存
                    ret: PARSE_MISS_COMMA_OR_SQUARE_BRACKET
                    break
                ]
            ]
        ]
        
        ;- 这里只有当解析失败时才需要释放由 malloc 分配在栈中的内存，
        ;- 因为解析成功时，分配的内存是用于存放解析得到的值，由调用者释放
        i: 0
        while [i < size] [
            free-value as json-value! (context-pop size? json-value!)
            i: i + 1
        ]

        ret
    ]

    parse-object: func [
        v       [json-value!]
        return: [json-parse-result!]
        /local
            ret     [integer!]
            size    [integer!]
            key-ptr [bytes-ptr!]
            len-ptr [int-ptr!]
            target  [byte-ptr!]
            m       [json-member! value]            ;- 加 value 修饰，避免静态分配
            i       [integer!]
    ][
        expect #"{"
        parse-whitespace                            ;- 第一个元素前可能有空白符
        if _ctx/json/1 = #"}" [
            _ctx/json: _ctx/json + 1
            v/type: JSON_OBJECT
            v/len: 0
            v/objs: null                          ;- 空对象
            return PARSE_OK
        ]
        ;printf ["    --- start parsing object ---^/"]
        ret: 0
        size: 0
            ;- 函数内的 /local 结构体默认是静态分配，调用多次之后都是同一个地址，不行，递归会导致覆盖
        m: declare json-member!
            ;- 栈分配，后面要 free，应该配合 malloc 才行
        ;m: as json-member! system/stack/allocate size? json-member!
            ;- 堆分配
        ;m: as json-member! allocate size? json-member!             
        len-ptr: declare int-ptr!
        key-ptr: declare bytes-ptr!
        key-ptr/bytes: declare byte-ptr!
        m/key: null     ;- 为了PARSE_MISS_KEY 时可以调用 free 而不报错

        forever [
            if _ctx/json/1 <> #"^"" [               ;- 不是 " 开头说明 key 不合法
                ret: PARSE_MISS_KEY
                break
            ]
 
            ;- 解析 key
            ret: parse-string-raw key-ptr len-ptr   ;- 为了返回多个值，用两个指针
            if ret <> PARSE_OK [
                ret: PARSE_MISS_KEY
                break
            ]
            ;- 分配内存装字符串，然后把新地址赋值给 key
            m/key: make-string key-ptr/bytes len-ptr/value
            ;printf ["parse-object m/key: %d -> %s^/" m/key m/key]
            m/klen: len-ptr/value

            parse-whitespace
            if _ctx/json/1 <> #":" [
                ret: PARSE_MISS_COLON
                break
            ]
            expect #":"
            parse-whitespace

            ;- 解析 value
            m/val: declare json-value!
            init-value m/val
            ;printf ["...parse-object starts m: %d, m/key: %d, m/klen: %d, m/val: %d, v: %d, v/objs: %d, m/key: %s^/" m m/key m/klen m/val v v/objs m/key]
            ret: parse-value m/val
            if ret <> PARSE_OK [break]
            ;printf ["...parse-object finish m: %d, m/key: %d, m/klen: %d, m/val: %d, v: %d, v/objs: %d^/" m m/key m/klen m/val v v/objs ]

            ;- 从栈中弹出空间构造成 json-member!
            target: context-push size? json-member!
            copy-memory target (as byte-ptr! m) (size? json-member!)
            size: size + 1
            m/key: null                             ;- 避免重复释放

            parse-whitespace                        ;- 每个元素结束后可能有空白符
            switch _ctx/json/1 [
                #"," [
                    _ctx/json: _ctx/json + 1        ;- 跳过逗号
                    parse-whitespace
                ]
                #"}" [
                    _ctx/json: _ctx/json + 1        ;- 对象结束，从栈中复制到 json-value!
                    v/type: JSON_OBJECT
                    v/len: size
                    size: size * size? json-member!
                    v/objs: allocate size
                    copy-memory v/objs (context-pop size) size    ;- 从栈中弹出

                    return PARSE_OK
                ]
                default [
                    ret: PARSE_MISS_COMMA_OR_CURLY_BRACKET
                    break
                ]
            ]
        ]
        
        ;- 这里只有当解析失败时才需要释放由 malloc 分配在栈中的内存，
        ;- 因为解析成功时，分配的内存是用于存放解析得到的值，由调用者释放
        free as byte-ptr! m/key
        i: 0
        while [i < size] [
            m: as json-member! (context-pop size? json-member!)
            free-value m/val
            i: i + 1
        ]

        ret
    ]

    parse-value: func [
        v       [json-value!]
        return: [json-parse-result!]
    ][
        switch _ctx/json/1 [
            #"n"    [return parse-null v]
            #"t"    [return parse-true v]
            #"f"    [return parse-false v]
            #"^""   [return parse-string v]
            #"["    [return parse-array v]
            #"{"    [return parse-object v]
            null-byte   [return PARSE_EXPECT_VALUE]
            default     [return parse-number v]
        ]
    ]

    parse: func [
        v       [json-value!]
        json    [c-string!]
        return: [json-parse-result!]
        /local  ret
    ][
        assert _ctx <> null

        _ctx/json:  json
        _ctx/stack: null
        _ctx/size:  0
        _ctx/top:   0
        v/type:     JSON_NULL

        ;printf ["^/--------- origin json: %s^/" json]
        parse-whitespace                ;- 先清掉前置的空白
        ret: parse-value v              ;- 开始解析
        if ret = PARSE_OK [
            parse-whitespace            ;- 再清理后续的空白

            if _ctx/json/1 <> null-byte [
                v/type: JSON_NULL
                ret: PARSE_ROOT_NOT_SINGULAR
            ]
        ]
 
        ;printf ["^/--------- parse finish stack size: %d, top: %d^/" _ctx/size _ctx/top]
        assert _ctx/top = 0             ;- 清理空间
        free _ctx/stack

        ret
    ]

    ;------------ Accessing functions -------------

    init-value: func [v [json-value!]][
        assert v <> null
        v/type: JSON_NULL
    ]

    free-value: func [v [json-value!] /local i e m][
        assert v <> null
        printf ["--free v: %d, type: %d^/" v v/type]
        switch v/type [
            JSON_STRING [
                printf ["free str: '%s' --> %d^/" v/str v/str]
                free as byte-ptr! v/str
            ]
            JSON_ARRAY  [
                i: 0
                while [i < v/len][
                    e: v/arr + i
                    i: i + 1
                    free-value e            ;- value! 可能有 str 类型的元素，让它递归
                ]
                free as byte-ptr! v/arr     ;- arr 本身也是 malloc 得到的
            ]
            JSON_OBJECT [
                i: 0
                while [i < v/len][
                    m: (as json-member! v/objs) + i
                    printf ["will free '%s' m/key @%d^/" m/key m/key]
                    free as byte-ptr! m/key
                    free-value m/val        ;- value 一定不为空
                    i: i + 1
                ]
                free v/objs
            ]
            default []
        ]
        v/type: JSON_NULL 
    ]

    get-type: func [v [json-value!] return: [json-type!]][
        assert v <> null
        v/type
    ]

    set-number: func [v [json-value!] num [float!]][
        free-value v
        v/num: num
        v/type: JSON_NUMBER
    ]

    get-number: func [v [json-value!] return: [float!]][
        assert all [
            v <> null
            v/type = JSON_NUMBER]
        v/num
    ]

    set-boolean: func [v [json-value!] b [logic!]][
        free-value v
        v/type: either b [JSON_TRUE][JSON_FALSE]
    ]

    get-boolean: func [v [json-value!] return: [logic!]][
        assert all [
            v <> null
            any [v/type = JSON_FALSE v/type = JSON_TRUE]]
        v/type = JSON_TRUE
    ]

    set-string: func [
        v       [json-value!]
        bytes   [byte-ptr!]
        len     [integer!]
    ][
        assert all [
            v <> null
            any [bytes <> null len = 0]]    ;- 非空指针，或空字符串
        
        free-value v    ;- 确保传入的 json-value! 中原有的 str/arr 被释放掉
        v/str: make-string bytes len
        v/len: len
        v/type: JSON_STRING
    ]

    get-string: func [v [json-value!] return: [c-string!]][
        assert all [
            v <> null
            v/type = JSON_STRING
            v/str <> null]
        v/str
    ]

    get-string-length: func [v [json-value!] return: [integer!]][
        assert all [
            v <> null
            v/type = JSON_STRING
            v/str <> null]
        v/len
    ]

    get-array-size: func [v [json-value!] return: [integer!]][
        assert all [
            v <> null
            v/type = JSON_ARRAY]
        v/len
    ]

    get-array-element: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [json-value!]
    ][
        assert all [
            v <> null
            v/type = JSON_ARRAY]
        assert index < v/len

        v/arr + index           ;- 下标基于 0
    ]

    get-object-size: func [v [json-value!] return: [integer!]][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        v/len
    ]

    get-object-key: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [c-string!]
        /local  member
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        assert index < v/len

        member: (as json-member! v/objs) + index
        member/key
    ]

    get-object-key-length: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [integer!]
        /local  member
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        assert index < v/len

        member: (as json-member! v/objs) + index
        member/klen
    ]

    get-object-value: func [
        v       [json-value!]
        index   [integer!]      ;- 下标基于 0
        return: [json-value!]
        /local  member
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT]
        assert index < v/len

        member: (as json-member! v/objs) + index
        member/val
    ]

    find-object-index: func [
        v       [json-value!]
        key     [c-string!]
        klen    [integer!]
        return: [integer!]
        /local  i m
    ][
        assert all [
            v <> null
            v/type = JSON_OBJECT
            key <> null]

        i: 0
        m: declare json-member!
        while [i < v/len][
            m: (as json-member! v/objs) + i 
            if all [
                m/klen = klen
                0 = compare-memory (as byte-ptr! m/key) (as byte-ptr! key) klen
            ][
                return i
            ]
            i: i + 1
        ]
        return KEY_NOT_EXIST
    ]

    find-object-value: func [
        v       [json-value!]
        key     [c-string!]
        klen    [integer!]
        return: [json-value!]
        /local  i e
    ][
        i: find-object-index v key klen
        if i = KEY_NOT_EXIST [return NULL]
        e: (as json-member! v/objs) + i
        e/val
    ]

    value-is-equal?: func [
        v1      [json-value!]
        v2      [json-value!]
        return: [logic!]
        /local  i j e1 e2 m1
    ][
        assert all [v1 <> null v2 <> null]

        if v1/type <> v2/type [return false]

        switch v1/type [
            JSON_STRING [
                return all [
                    v1/len = v2/len
                    0 = compare-memory (as byte-ptr! v1/str) (as byte-ptr! v2/str) v1/len
                ]
            ]
            JSON_NUMBER [return v1/num = v2/num]
            JSON_ARRAY  [
                if v1/len <> v2/len [return false]
                i: 0
                while [i < v1/len][
                    e1: (as json-value! v1/arr) + i
                    e2: (as json-value! v2/arr) + i
                    unless value-is-equal? e1 e2 [return false]
                    i: i + 1
                ]
                return true
            ]
            JSON_OBJECT [
                if v1/len <> v2/len [return false]          ;- 对象内的 kv 个数不同
                i: 0
                while [i < v1/len][                         ;- 遍历 v1 中的元素，在 v2 找
                    m1: (as json-member! v1/objs) + i
                    ;printf ["value-is-equal? i: %d, key: %s, klen: %d^/" i m1/key  m1/klen]
                    e2: find-object-value v2 m1/key m1/klen

                    if null? e2 [return false]
                    if not value-is-equal? m1/val e2 [return false]
                    i: i + 1
                ]
                return true
            ]
            default [return true]       ;- 剩下的是 TRUE / FALSE / NULL
        ]
    ]

    copy-value: func [
        dst     [json-value!]
        src     [json-value!]
        /local size target i v v0 m m0 tmp
    ][
        assert all [
            src <> null
            dst <> null
            src <> dst
        ]

        switch src/type [
            JSON_STRING [
                set-string dst (as byte-ptr! src/str) src/len
            ]
            JSON_ARRAY [
                size: src/len * (size? json-value!)
                target: allocate size
                copy-memory (as byte-ptr! dst) (as byte-ptr! src) (size? json-value!)

                i: 0
                v: declare json-value!
                while [i < src/len][
                    v: (as json-value! target) + i
                    v0: src/arr + i
                    copy-value v v0          ;- 递归复制
                    i: i + 1
                ]
                
                dst/arr: as json-value! target          ;- 指向新的起始地址
            ]
            JSON_OBJECT [
                size: src/len * (size? json-member!)
                target: allocate size                   ;- 申请足够的内存来保存成员

                ;- 先整个复制
                copy-memory target src/objs size
                copy-memory (as byte-ptr! dst) (as byte-ptr! src) (size? json-member!)

                ;- 再单独处理 string、value 等需要分配内存的元素
                i: 0
                while [i < src/len][
                    m: (as json-member! target) + i
                    m0: (as json-member! src/objs) + i

                    m/key: make-string (as byte-ptr! m0/key) m0/klen
                    m/klen: m0/klen

                    copy-value m/val m0/val             ;- 递归复制 value
                    i: i + 1
                ]
                dst/objs: target                        ;- 指向新的起始地址
            ]
            default [
                free-value dst
                ;printf ["copy default^/"]
                copy-memory (as byte-ptr! dst) (as byte-ptr! src) (size? json-value!)
            ]
        ]
    ]

    move-value: func [
        dst [json-value!]
        src [json-value!]
    ][
        assert all [
            dst <> null
            src <> null
            src <> dst
        ]
        free-value dst
        copy-memory (as byte-ptr! dst) (as byte-ptr! src) (size? json-value!)
        init-value src
    ]

    swap-value: func [
        v1  [json-value!]
        v2  [json-value!]
        /local tmp
    ][
        assert all [v1 <> null v2 <> null]
        if v1 <> v2 [
            tmp: declare json-value!
            copy-memory (as byte-ptr! tmp) (as byte-ptr! v1) (size? json-value!)
            copy-memory (as byte-ptr! v1) (as byte-ptr! v2) (size? json-value!)
            copy-memory (as byte-ptr! v2) (as byte-ptr! tmp) (size? json-value!)
        ]
    ]
]


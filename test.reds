Red/System []

#include %json.reds


main-ret:   0
test-count: 0
test-pass:  0
test-index: 0

#define EXPECT_EQ_BASE(equality expect actual format) [
    test-count: test-count + 1
    test-index: test-index + 1
    either equality [
        test-pass: test-pass + 1
        ;printf ["---> PASSED %d, expect: %d, actual: %d" test-index expect actual]
        ;print lf
    ][
        s: as-c-string allocate 270  ;- 预分配 format 串的长度
        sprintf [s "---> FAILED %d, expect: %s, actual: %s" test-index format format]
        printf [s expect actual]
        print lf
        main-ret: 1
    ]
]

expect-eq-int?: func [
    expect  [integer!]
    actual  [integer!]
    /local equality s
][
    equality: expect = actual
    EXPECT_EQ_BASE(equality expect actual "%d")
]

expect-eq-float?: func [
    expect  [float!]
    actual  [float!]
    /local equality s
][
    equality: expect = actual
    EXPECT_EQ_BASE(equality expect actual "%.17g")
]

expect-eq-string?: func [
    expect  [c-string!]
    actual  [c-string!]
    len     [integer!]
    /local equality s
][
    ;printf ["eq-string? expect: %s, actual: %s.^/" expect actual]
    equality: all [
                len = length? expect        ;- 长度必须相同
                zero? compare-memory        ;- 再逐个字节来比较
                        as byte-ptr! expect
                        as byte-ptr! actual
                        len]
    EXPECT_EQ_BASE(equality expect actual "%s")
]

expect-true?: func [
    actual  [logic!]
    /local  equality s
][
    equality: actual = true
    EXPECT_EQ_BASE(equality "true" "false" "%s")
]

expect-false?: func [
    actual  [logic!]
    /local  equality s
][
    equality: actual = false
    EXPECT_EQ_BASE(equality "false" "true" "%s")
]

test-parse-null: func [/local v][
    v: declare json-value!
    v/type: JSON_NULL
    expect-eq-int? PARSE_OK json/parse v "null"
    expect-eq-int? JSON_NULL json/get-type v
    json/free-value v
]

test-parse-true: func [/local v][
    v: declare json-value!
    v/type: JSON_TRUE
    expect-eq-int? PARSE_OK json/parse v "true"
    expect-eq-int? JSON_TRUE json/get-type v
    json/free-value v
]

test-parse-false: func [/local v][
    v: declare json-value!
    v/type: JSON_FALSE
    expect-eq-int? PARSE_OK json/parse v "false"
    expect-eq-int? JSON_FALSE json/get-type v
    json/free-value v
]

#define TEST_ERROR(expect str) [
    v: declare json-value!  ;- 会多次调用，测试期间无所谓
    v/type: JSON_NULL
    expect-eq-int? expect json/parse v str
    expect-eq-int? JSON_NULL json/get-type v
    json/free-value v
]

test-parse-expect-value: func [/local v][
    TEST_ERROR(PARSE_EXPECT_VALUE "")
    TEST_ERROR(PARSE_EXPECT_VALUE " ")
]

test-parse-invalid-value: func [/local v][
    TEST_ERROR(PARSE_INVALID_VALUE "nul")
    TEST_ERROR(PARSE_INVALID_VALUE "?")    

    ;/* invalid number */
    TEST_ERROR(PARSE_INVALID_VALUE "+0");
    TEST_ERROR(PARSE_INVALID_VALUE "+1");
    TEST_ERROR(PARSE_INVALID_VALUE ".123"); /* at least one digit before '.' */
    TEST_ERROR(PARSE_INVALID_VALUE "1.");   /* at least one digit after '.' */

    ; invalid value in array 即栈中有内存未释放
    TEST_ERROR(PARSE_INVALID_VALUE "[1,]")
    TEST_ERROR(PARSE_INVALID_VALUE {["a", nul]})
]

test-parse-root-not-singular: func [/local v][
    TEST_ERROR(PARSE_ROOT_NOT_SINGULAR "null x")

    ;/* invalid number */
    TEST_ERROR(PARSE_ROOT_NOT_SINGULAR "0123"); /* after zero should be '.' or nothing */
    TEST_ERROR(PARSE_ROOT_NOT_SINGULAR "0x0");
    TEST_ERROR(PARSE_ROOT_NOT_SINGULAR "0x123");
]

#define TEST_NUMBER(expect str) [
    v: declare json-value!  ;- 会重复调用，测试期间无所谓
    expect-eq-int? PARSE_OK json/parse v str
    expect-eq-int? JSON_NUMBER json/get-type v
    expect-eq-float? expect json/get-number v
    json/free-value v
]

test-parse-number: func [/local v][
    TEST_NUMBER(0.0 "0")
    TEST_NUMBER(0.0 "-0")
    TEST_NUMBER(0.1 "0.1")
    TEST_NUMBER(3.1416 "3.1416")
    TEST_NUMBER(1.5 "1.5")
    TEST_NUMBER(-1.5 "-1.5")
    TEST_NUMBER(0.0 "-0.0")
    TEST_NUMBER(1.0 "1")
    TEST_NUMBER(-1.0 "-1")
    TEST_NUMBER(1E10 "1E10")
    TEST_NUMBER(1e10 "1e10")
    TEST_NUMBER(1E+10 "1E+10")
    TEST_NUMBER(1E-10 "1E-10")
    TEST_NUMBER(-1E10 "-1E10")
    TEST_NUMBER(-1e10 "-1e10")
    TEST_NUMBER(-1E+10 "-1E+10")
    TEST_NUMBER(-1E-10 "-1E-10")
    TEST_NUMBER(1.234E+10 "1.234E+10")
    TEST_NUMBER(1.234E-10 "1.234E-10")

    TEST_NUMBER(0.0 "1e-10000") ; must underflow
    TEST_NUMBER(1.0000000000000002 "1.0000000000000002"); /* the smallest number > 1 */
    TEST_NUMBER( 4.9406564584124654e-324 "4.9406564584124654e-324"); /* minimum denormal */
    TEST_NUMBER(-4.9406564584124654e-324 "-4.9406564584124654e-324");
    TEST_NUMBER( 2.2250738585072009e-308 "2.2250738585072009e-308");  /* Max subnormal double */
    TEST_NUMBER(-2.2250738585072009e-308 "-2.2250738585072009e-308");
    TEST_NUMBER( 2.2250738585072014e-308 "2.2250738585072014e-308");  /* Min normal positive double */
    TEST_NUMBER(-2.2250738585072014e-308 "-2.2250738585072014e-308");
    TEST_NUMBER( 1.7976931348623157e+308 "1.7976931348623157e+308");  /* Max double */
    TEST_NUMBER(-1.7976931348623157e+308 "-1.7976931348623157e+308");
]

test-parse-number-too-big: func [/local v][
    TEST_ERROR(PARSE_NUMBER_TOO_BIG "1e309")
    TEST_ERROR(PARSE_NUMBER_TOO_BIG "-1e309")
]

test-access-string: func [/local v][
    v: declare json-value!
    json/init-value v

    json/set-string v as byte-ptr! "" 0
    expect-eq-string? "" json/get-string v json/get-string-length v

    json/set-string v as byte-ptr! "hello" 5
    expect-eq-string? "hello" json/get-string v json/get-string-length v

    json/free-value v
]

test-access-boolean: func [/local v][
    v: declare json-value!
    json/init-value v

    json/set-string v as byte-ptr! "a" 1
    json/set-boolean v true
    expect-true? json/get-boolean v
    json/set-boolean v false
    expect-false? json/get-boolean v

    json/free-value v
]

test-access-number: func [/local v][
    v: declare json-value!
    json/init-value v

    json/set-string v as byte-ptr! "a" 1
    json/set-number v 3.14
    expect-eq-float? 3.14 json/get-number v

    json/free-value v
]

#define TEST_STRING(expect str) [
    v: declare json-value!
    json/init-value v

    expect-eq-int? PARSE_OK json/parse v str
    expect-eq-int? JSON_STRING json/get-type v
    expect-eq-string? expect json/get-string v json/get-string-length v

    json/free-value v
]

test-parse-string: func [/local v][
    TEST_STRING("ab123" {"ab123"})
    TEST_STRING(""      {""})
    TEST_STRING("hello" {"hello"})
    TEST_STRING("hello red" {"hello red"})
    TEST_STRING("^""    {"\""})
    TEST_STRING("\"     {"\\"})
    TEST_STRING({\" \\ / \n \r \t}  {"\\\" \\\\ \/ \\n \\r \\t"})
]

test-parse-array: func [/local v e i j v1 v2][
    v: declare json-value!
    json/init-value v

    expect-eq-int? PARSE_OK json/parse v "[ ]"
    expect-eq-int? JSON_ARRAY json/get-type v
    expect-eq-int? 0 json/get-array-size v

    expect-eq-int? PARSE_OK json/parse v " [ 1 , 2 ] "
    expect-eq-int? JSON_ARRAY json/get-type v
    expect-eq-int? 2 json/get-array-size v

    e: json/get-array-element v 0
    expect-eq-float? 1.0 e/num

    expect-eq-int? PARSE_OK json/parse v {[ null , false , true , 123 , "abc" ]}
    expect-eq-int? JSON_ARRAY json/get-type v
    expect-eq-int? 5 json/get-array-size v

    e: json/get-array-element v 0
    expect-eq-int? JSON_NULL json/get-type e
    e: json/get-array-element v 1
    expect-eq-int? JSON_FALSE json/get-type e
    e: json/get-array-element v 2
    expect-eq-int? JSON_TRUE json/get-type e
    e: json/get-array-element v 3
    expect-eq-int? JSON_NUMBER json/get-type e
    e: json/get-array-element v 4
    expect-eq-int? JSON_STRING json/get-type e

    e: json/get-array-element v 3
    expect-eq-float? 123.0 json/get-number e
    e: json/get-array-element v 4
    expect-eq-string? "abc" json/get-string e json/get-string-length e

    expect-eq-int? PARSE_OK json/parse v {[ [ ] , [ 0 ] , [ 0 , 1 ] , [ 0 , 1 , 2 ] ]}
    expect-eq-int? JSON_ARRAY json/get-type v
    expect-eq-int? 4 json/get-array-size v

    i: json/get-array-size v
    while [i > 0] [
        v1: declare json-value!
        json/init-value v1

        v1: json/get-array-element v (4 - i)
        expect-eq-int? JSON_ARRAY json/get-type v1
        expect-eq-int? (4 - i) json/get-array-size v1

        j: 0
        while [j < (4 - i)] [
            ;printf ["i:%d, j:%d^/" (4 - i) j]
            v2: declare json-value!
            json/init-value v2 

            v2: json/get-array-element v1 j
            expect-eq-int? JSON_NUMBER json/get-type v2
            expect-eq-float? as-float j json/get-number v2 j
            j: j + 1
        ]

        i: i - 1
    ]

    e: json/get-array-element v 3
    expect-eq-int? JSON_ARRAY json/get-type e
    e: json/get-array-element e 1
    expect-eq-float? 1.0 e/num

    json/free-value v
    json/free-value v1
    json/free-value v2
    json/free-value e
]

test-parse-miss-key: func [/local v][
    TEST_ERROR(PARSE_MISS_KEY "{ :1 ,")
    TEST_ERROR(PARSE_MISS_KEY "{1:1,")
    TEST_ERROR(PARSE_MISS_KEY "{true:1,")
    TEST_ERROR(PARSE_MISS_KEY "{false:1,")
    TEST_ERROR(PARSE_MISS_KEY "{null:1,")
    TEST_ERROR(PARSE_MISS_KEY "{[]:1,")
    TEST_ERROR(PARSE_MISS_KEY "{^"ab^":1,")
]

test-parse-miss-colon: func [/local v][
    TEST_ERROR(PARSE_MISS_COLON "{^"aa^"}")
    TEST_ERROR(PARSE_MISS_COLON "{^"aaa^", ^"b^"}")
]

test-parse-miss-comma-or-curly-bracket: func [/local v][
    TEST_ERROR(PARSE_MISS_COMMA_OR_CURLY_BRACKET "{^"a^":1")
    TEST_ERROR(PARSE_MISS_COMMA_OR_CURLY_BRACKET "{^"ab^":1]")
    TEST_ERROR(PARSE_MISS_COMMA_OR_CURLY_BRACKET "{^"abc^":1  ^"bb^"")
    TEST_ERROR(PARSE_MISS_COMMA_OR_CURLY_BRACKET "{^"abcd^": {}")
]

test-parse-object: func [/local v][
    v: declare json-value!
    json/init-value v
    expect-eq-int? PARSE_OK json/parse v " { } "
    expect-eq-int? JSON_OBJECT json/get-type v
    expect-eq-int? 0 json/get-object-size v
    json/free-value v
]

test-parse-object1: func [/local v v1 v2][
    v: declare json-value!
    v1: declare json-value!
    v2: declare json-value!
    json/init-value v
    json/init-value v1
    json/init-value v2

    expect-eq-int? PARSE_OK json/parse v "{ ^"a^" : [1 , ^"value1^"] , ^"b^": ^"bbb^" , ^"c^": 123}"
    expect-eq-int? JSON_OBJECT json/get-type v
    expect-eq-int? 3 json/get-object-size v
    expect-eq-string? "a" (json/get-object-key v 0) (json/get-object-key-length v 0)
    v1: json/get-object-value v 0
        v2: json/get-object-value v 1
        ;printf ["v1: %d, v2: %d^/" v1 v2]       ;- 查 member! 的 json-value! 引用有 bug 时用的
        assert v1 <> v2
    expect-eq-int? JSON_ARRAY json/get-type v1
    expect-eq-int? 2 json/get-array-size v1
    v2: json/get-array-element v1 0
    expect-eq-int? JSON_NUMBER json/get-type v2
    expect-eq-float? 1.0 json/get-number v2
    v2: json/get-array-element v1 1
    expect-eq-int? JSON_STRING json/get-type v2
    expect-eq-string? "value1" (json/get-string v2) (json/get-string-length v2)

    v1: json/get-object-value v 1
    expect-eq-int? JSON_STRING json/get-type v1
    expect-eq-string? "bbb" (json/get-string v1) (json/get-string-length v1)

    v1: json/get-object-value v 2
    expect-eq-int? JSON_NUMBER json/get-type v1
    expect-eq-float? 123.0 json/get-number v1

    json/free-value v
    json/free-value v1
    json/free-value v2
]

test-parse-object2: func [/local v v1 i][
    v: declare json-value!
    json/init-value v

    expect-eq-int? PARSE_OK json/parse v { { 
        ^"n^" : null ,
        ^"f^" : false,
        ^"t^" : true ,
        ^"i^" : 1234 ,
        ^"s^" : ^"i am string^" ,
        ^"a^" : [ 1 , 2, ^"cc^" ] ,
        ^"o^" : { ^"1^": 1, ^"2^" : 2, ^"kkk^": ^"abc^" }
    } }
    expect-eq-int? JSON_OBJECT json/get-type v
    expect-eq-int? 7 json/get-object-size v

    expect-eq-string? "n" (json/get-object-key v 0) (json/get-object-key-length v 0)
    expect-eq-int? JSON_NULL json/get-type (json/get-object-value v 0)

    expect-eq-string? "f" (json/get-object-key v 1) (json/get-object-key-length v 1)
    expect-eq-int? JSON_FALSE json/get-type (json/get-object-value v 1)

    expect-eq-string? "t" (json/get-object-key v 2) (json/get-object-key-length v 2)
    expect-eq-int? JSON_TRUE json/get-type (json/get-object-value v 2)

    expect-eq-string? "i" (json/get-object-key v 3) (json/get-object-key-length v 3)
    expect-eq-int? JSON_NUMBER json/get-type (json/get-object-value v 3)

    expect-eq-string? "s" (json/get-object-key v 4) (json/get-object-key-length v 4)
    expect-eq-int? JSON_STRING json/get-type (json/get-object-value v 4)

    expect-eq-string? "a" (json/get-object-key v 5) (json/get-object-key-length v 5)
    expect-eq-int? JSON_ARRAY json/get-type (json/get-object-value v 5)
    v1: declare json-value!
    i: 0
    while [i < 2][
        json/init-value v1
        v1: json/get-array-element (json/get-object-value v 5) i
        expect-eq-int? JSON_NUMBER json/get-type v1
        expect-eq-float? (1.0 + i) json/get-number v1
        i: i + 1
    ]

    expect-eq-string? "o" (json/get-object-key v 6) (json/get-object-key-length v 6)
    expect-eq-int? JSON_OBJECT json/get-type (json/get-object-value v 6)
    i: 0
    while [i < 2][
        json/init-value v1
        v1: json/get-object-value (json/get-object-value v 6) i
        expect-eq-int? JSON_NUMBER json/get-type v1
        expect-eq-float? (1.0 + i) json/get-number v1
        expect-eq-int? 1 (json/get-object-key-length (json/get-object-value v 6) i)
        i: i + 1
    ]

    json/free-value v
    json/free-value v1
]

TEST_EQUAL: func [json1 [c-string!] json2 [c-string!] equality [logic!] /local v1 v2] [
    v1: declare json-value!
    v2: declare json-value!
    json/init-value v1
    json/init-value v2
    expect-eq-int? PARSE_OK json/parse v1 json1
    expect-eq-int? PARSE_OK json/parse v2 json2
    either equality [
        expect-true? json/value-is-equal? v1 v2
    ][
        expect-false? json/value-is-equal? v1 v2
    ]
    json/free-value v1
    json/free-value v2
]

test-equal: does [
    TEST_EQUAL "true" "true" true
    TEST_EQUAL "true" "false" false
    TEST_EQUAL "false" "false" true
    TEST_EQUAL "null" "null" true
    TEST_EQUAL "null" "0" false
    TEST_EQUAL "123" "123" true
    TEST_EQUAL "123" "456" false
    TEST_EQUAL {"abc"} {"abc"} true
    TEST_EQUAL {"abc"} {"abcd"} false
    TEST_EQUAL "[]" "[ ]" true
    TEST_EQUAL "[]" "null" false
    TEST_EQUAL "[1, 2,3]" "[1,2, 3]" true
    TEST_EQUAL "[1, 2,3]" "[1,2, 3,4]" false
    TEST_EQUAL "[[]]" "[[]]" true
    TEST_EQUAL "{}" "{ }" true
    TEST_EQUAL "{}" "null" false
    TEST_EQUAL "{}" "[]" false
               
    TEST_EQUAL "{^"a^":1,^"b^":2}" "{^"a^":1,^"b^":2}" true
    TEST_EQUAL "{^"a^":1,^"b^":2}" "{^"b^":2,^"a^":1}" true
    TEST_EQUAL "{^"a^":1,^"b^":2}" "{^"a^":1,^"b^":3}" false
    TEST_EQUAL "{^"a^":1,^"b^":2}" "{^"a^":1,^"b^":2,^"c^":3}" false
    TEST_EQUAL "{^"a^":{^"b^":{^"c^":{}}}}" "{^"a^":{^"b^":{^"c^":{}}}}" true
    TEST_EQUAL "{^"a^":{^"b^":{^"c^":{}}}}" "{^"a^":{^"b^":{^"c^":[]}}}" false
]

test-copy-array: func [/local v1 v2][
    v1: declare json-value!
    json/init-value v1
    expect-eq-int? PARSE_OK json/parse v1 {["abc", 123, true, false, null, ["a", 123]]}
    ;expect-eq-int? PARSE_OK json/parse v1 {[1, 123, true, false, null]}

    v2: declare json-value!
    json/init-value v2
    json/copy-value v2 v1

    expect-true? json/value-is-equal? v2 v1

    json/free-value v1
    json/free-value v2
]

test-copy-object: func [/local v1 v2][
    v1: declare json-value!
    json/init-value v1
    expect-eq-int? PARSE_OK json/parse v1 "{^"t^":true,^"f^":false,^"n^":null,^"d^":1.5,^"a^":[1,2,3]}"
    ;expect-eq-int? PARSE_OK json/parse v1 "{^"key^":true}"
    expect-eq-int? JSON_OBJECT json/get-type v1

    v2: declare json-value!
    json/init-value v2
    json/copy-value v2 v1

    expect-true? json/value-is-equal? v2 v1

    json/free-value v1
    json/free-value v2
]

test-move: func [/local v1 v2 v3][
    v1: declare json-value!
    json/init-value v1
    expect-eq-int? PARSE_OK json/parse v1  "{^"t^":true,^"f^":false,^"n^":null,^"d^":1.5,^"a^":[1,2,3]}"

    v2: declare json-value!
    json/init-value v2
    json/copy-value v2 v1       ;- 复制

    v3: declare json-value!
    json/init-value v3 
    json/move-value v3 v2       ;- move

    printf ["    v1: %d, v2: %d, v3: %d^/" v1 v2 v3]
    expect-eq-int? JSON_NULL json/get-type v2
    expect-true? json/value-is-equal? v3 v1

    json/free-value v1
    json/free-value v2
    json/free-value v3
]

test-parse: does [
    ;test-parse-number-too-big      ;- no working
    test-parse-null
    test-parse-true
    test-parse-false
    test-parse-expect-value
    test-parse-invalid-value
    test-parse-root-not-singular
    test-parse-number
    test-parse-string
    test-parse-array

    test-access-string
    test-access-boolean
    test-access-number

    test-parse-miss-key
    test-parse-miss-colon
    test-parse-miss-comma-or-curly-bracket
    test-parse-object
    test-parse-object1
    test-parse-object2
]

main: does [
    test-parse
    test-equal
    print-line ["---- test-copy-array -----"]
    test-copy-array
    test-copy-object
    test-move

    comment { 
        test-parse 和 copy-array 同时运行时在 macOS 下会偶尔遇到两次 free 相同
        地址的问题，发现是 malloc 字符串前后分配了相同地址。
        但在 Win7 下没有这种情况。
    }

    either zero? test-count [
        printf ["    >>> Nothing to test^/^/"]
    ][
        printf ["    >>> %d/%d (%3.2f%%) passed^/^/" test-pass test-count (100.0 * test-pass / test-count)]
    ]
]

main


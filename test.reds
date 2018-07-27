Red/System []

#include %reds-json.reds


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

expect-eq-int: func [
    expect  [integer!]
    actual  [integer!]
    /local equality s
][
    equality: expect = actual
    EXPECT_EQ_BASE(equality expect actual "%d")
]

expect-eq-float: func [
    expect  [float!]
    actual  [float!]
    /local equality s
][
    equality: expect = actual
    EXPECT_EQ_BASE(equality expect actual "%.17g")
]

expect-eq-string: func [
    expect  [c-string!]
    actual  [c-string!]
    len     [integer!]
    /local equality s
][
    print-line ["eq-string? expect: " expect ", actual: " actual "."]
    equality: all [
                len = length? expect        ;- 长度必须相同
                zero? compare-memory        ;- 再逐个字节来比较
                        as byte-ptr! expect
                        as byte-ptr! actual
                        len]
    EXPECT_EQ_BASE(equality expect actual "%s")
]

expect-true: func [
    actual  [logic!]
    /local  equality s
][
    equality: actual = true
    EXPECT_EQ_BASE(equality "true" "false" "%s")
]

expect-false: func [
    actual  [logic!]
    /local  equality s
][
    equality: actual = false
    EXPECT_EQ_BASE(equality "false" "true" "%s")
]

test-parse-null: func [/local v][
    v: declare json-value!
    v/type: JSON_NULL
    expect-eq-int PARSE_OK json/parse v "null"
    expect-eq-int JSON_NULL json/get-type v
]

test-parse-true: func [/local v][
    v: declare json-value!
    v/type: JSON_TRUE
    expect-eq-int PARSE_OK json/parse v "true"
    expect-eq-int JSON_TRUE json/get-type v
]

test-parse-false: func [/local v][
    v: declare json-value!
    v/type: JSON_FALSE
    expect-eq-int PARSE_OK json/parse v "false"
    expect-eq-int JSON_FALSE json/get-type v
]

#define TEST_ERROR(expect str) [
    v: declare json-value!  ;- 会重复调用，测试期间无所谓
    v/type: JSON_FALSE
    expect-eq-int expect json/parse v str
    expect-eq-int JSON_NULL json/get-type v
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
    expect-eq-int PARSE_OK json/parse v str
    expect-eq-int JSON_NUMBER json/get-type v
    expect-eq-float expect json/get-number v
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
    expect-eq-string "" json/get-string v json/get-string-length v

    json/set-string v as byte-ptr! "hello" 5
    expect-eq-string "hello" json/get-string v json/get-string-length v

    json/free-value v
]

test-access-boolean: func [/local v][
    v: declare json-value!
    json/init-value v

    json/set-string v as byte-ptr! "a" 1
    json/set-boolean v true
    expect-true json/get-boolean v
    json/set-boolean v false
    expect-false json/get-boolean v

    json/free-value v
]

test-access-number: func [/local v][
    v: declare json-value!
    json/init-value v

    json/set-string v as byte-ptr! "a" 1
    json/set-number v 3.14
    expect-eq-float 3.14 json/get-number v

    json/free-value v
]

#define TEST_STRING(expect str) [
    v: declare json-value!
    json/init-value v

    expect-eq-int PARSE_OK json/parse v str
    expect-eq-int JSON_STRING json/get-type v
    expect-eq-string expect json/get-string v json/get-string-length v

    json/free-value v
]

test-parse-string: func [/local v][
    TEST_STRING("ab123" {"ab123"})
    print-line "-------"
    TEST_STRING("" {""})
    print-line "-------"
    TEST_STRING("hello" {"hello"})
    print-line "-------"
    TEST_STRING("hello red" {"hello red"})
    print-line "-------"
    TEST_STRING("^""    {"\""})
    TEST_STRING("\"     {"\\"})
    TEST_STRING({\" \\ / \n \r \t}  {"\\\" \\\\ \/ \\n \\r \\t"})
    print-line "-------"
]

test-parse-array: func [/local v e][
    v: declare json-value!
    json/init-value v

    expect-eq-int PARSE_OK json/parse v "[ ]"
    expect-eq-int JSON_ARRAY json/get-type v
    expect-eq-int 0 json/get-array-size v

    expect-eq-int PARSE_OK json/parse v " [ 1 , 2 ] "
    expect-eq-int JSON_ARRAY json/get-type v
    expect-eq-int 2 json/get-array-size v

    e: json/get-array-element v 0
    expect-eq-float 1.0 e/num

    expect-eq-int PARSE_OK json/parse v {[ null , false , true , 123 , "abc" ]}
    expect-eq-int JSON_ARRAY json/get-type v
    expect-eq-int 5 json/get-array-size v

    e: json/get-array-element v 4
    expect-eq-string "abc" json/get-string e json/get-string-length e
    e: json/get-array-element v 1
    expect-eq-int JSON_FALSE json/get-type e

    expect-eq-int PARSE_OK json/parse v {[ [ ] , [ 0 ] , [ 0 , 1 ] , [ 0 , 1 , 2 ] ]}
    expect-eq-int JSON_ARRAY json/get-type v
    expect-eq-int 4 json/get-array-size v

    e: json/get-array-element v 3
    expect-eq-int JSON_ARRAY json/get-type e
    e: json/get-array-element e 1
    expect-eq-float 1.0 e/num

    json/free-value v
    json/free-value e
]

test-parse: does [
    ;test-parse-null
    ;test-parse-true
    ;test-parse-false
    ;test-parse-expect-value
    ;test-parse-invalid-value
    ;test-parse-root-not-singular
    ;test-parse-number
    ;test-parse-number-too-big      ;- no working

    ;test-parse-string
    test-parse-array

    ;test-access-string
    ;test-access-boolean
    ;test-access-number

]

main: func [return: [integer!]][
    test-parse

    printf ["%d/%d (%3.2f%%) passed" test-pass test-count
        100.0 * test-pass / test-count]
    print lf

    main-ret
]

main


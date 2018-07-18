Red/System []

#include %reds-json.reds


main-ret:   0
test-count: 0
test-pass:  0
test-index: 0

expect-eq-base: func [
    equality    [logic!]
    expect      [integer!]
    actual      [integer!]
    format      [c-string!]
][
    test-count: test-count + 1
    test-index: test-index + 1
    either equality [
        test-pass: test-pass + 1
        ;printf ["---> PASSED %d, expect: %d, actual: %d" test-index expect actual]
        ;print lf
    ][
        printf ["---> FAILED %d, expect: %d, actual: %d" test-index expect actual]
        print lf
        main-ret: 1
    ]
]

expect-eq-int: func [
    expect  [integer!]
    actual  [integer!]
    /local
        equality    [logic!]
][
    equality: expect = actual
    expect-eq-base equality expect actual "%d"
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
]

test-parse-root-not-singular: func [/local v][
    TEST_ERROR(PARSE_ROOT_NOT_SINGULAR "null x")
]

test-parse: does [
    test-parse-null
    test-parse-true
    test-parse-false
    test-parse-expect-value
    test-parse-invalid-value
    test-parse-root-not-singular
]

main: func [return: [integer!]][
    test-parse

    printf ["%d/%d (%3.2f%%) passed" test-pass test-count
        100.0 * test-pass / test-count]
    print lf

    main-ret
]

main


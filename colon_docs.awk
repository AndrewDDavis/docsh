# colon_docs
#
# Capture docs from lines with leading ' : ' at the top of a function definition. This
# code is called from docsh to capture function docs.
#
# Notes:
#
# - comments are not a problem, whether on their own line or at the end of a line; they
#   are not printed by 'declare -pf'
# - likewise, empty lines and extra whitespace at the end of a line are stripped away
# - when a quoted string carries on past the newline, there is no ';'
# - escaped newlines are removed from the stream by the shell
#
# E.g. output to be parsed from: `declare -pf foo | sed 's/$/::/'`:
#   foo () ::
#   { ::
#       : this line is not quoted;::
#       : "this is a quoted str";::
#       : 'this is single-quoted';::
#       : "this line has some extra space";::
#       : "this string goes::
#     over::
#     multiple lines";::
#       : "here is an escaped \" quote";::
#       : "this one " carries on after the close;::
#       : this is continued by escaping the newline;::
#       : "so is this";::
#       local r=1;::
#       echo $r;::
#       echo hi::
#   }::
#

BEGIN {
    # regex to match colon lines
    # - also allows the 'false && : ...' idiom
    # - and, for functions wrapped in (...), ( : "...
    #r_col = "^[[:blank:]]*(false && )?:[[:blank:]]*"
    r_col = "^[[:blank:]]*(\( |false[[:blank:]]+&&[[:blank:]]+)?:[[:blank:]]+"

    # - also sometimes good to allow the 'docsh -TD "...' idiom
    r_dcsh = "^[[:blank:]]*docsh[[:blank:]]+(-[[:alnum:]]+[[:blank:]]+)*"

    # regex for here-doc start
    r_hds = ( r_col "<<-?[[:blank:]]?['\"]?([[:alnum:]_]+)['\"]?$" )

    docstr = ""
}

# debug
# { print "parsing line: <" $0 ">" > "/dev/stderr"; }


# Skip first 2 lines
NR<=2 { next; }

# Skip empty lines, e.g. after a here-doc
/^[[:blank:]]*$/ { next; }

# Skip a test on line 3, e.g. [[ $# -eq 0 ]] && { ...
# - NB, no matter how it's written in the source, declare -pf will always print the
#   brace on the same line as [[ ... ]].
{ if ( NR == 3  &&  $0 ~ /^[[:blank:]]*\[\[/ ) next; }

# Quit on other non colon lines
$0 !~ r_col  &&  $0 !~ (r_dcsh "['\"]") \
    { exit ( length(docstr) == 0 ); }

# Main loop
{
    # test for various doc forms
    if ( match($0, r_hds) ) {
        # colon here-doc found
        read_heredocs()
    }
    else if ( read_quotdocs("'") || read_quotdocs("\"") ) {
        # quoted colon doc line was found and read to docstr
    }
    else if ( match($0, r_col) ) {
        # unquoted colon string
        read_colondocs()
    }
    else {
        # no match
        # - this shouldn't happen, as the test above should have quit
        print "no q-docs on line " NR ": " $0 > "/dev/stderr"
    }
    next
}

END {
    if ( length(docstr) > 0 ) {

        # prevent extra newline
        ORS = ""

        print docstr
    }
}

function read_colondocs() {

    # - the shell will have stripped repeated whitespace

    # match: RSTART has start index (from 1), RLENGTH has char length of match
    # - leave off the end semicolon
    s = substr($0, RLENGTH+1, length($0)-RLENGTH-1)

    docstr = docstr s "\n"
}

function read_quotdocs(q) {

    if ( match($0, r_col q) || match($0, r_dcsh q) ) {

        # quoted string
        # match(s,r): RSTART has start index (from 1), RLENGTH has char length of match
        # substr(s,i,[n]): returns substring of s starting at i
        s = substr($0, RLENGTH + 1)

        # debug
        # print "substr <" s "> from <" $0 ">" > "/dev/stderr"

        # test for multi-line quote, in which line won't end with ';'
        while ( ! match(s, ";$") ) {

            # string continues
            s = repl_escchars(s)
            docstr = docstr s "\n"

            if ( ! getline s ) break

            # debug
            # print "continuing with <" s ">" > "/dev/stderr"
        }

        # string has ended
        # - strip semicolon and possible quote at end
        gsub(q "?;$", "", s)

        # deal with special chars in double-quoted strings
        if ( q == "\"" ) {
            # strip non-escaped quotes
            # - this is tricky without back-references
            if ( match(s, /[^\134]\42/) ) {

                s = substr(s, 1, RSTART) substr(s, RSTART+2)
            }

            # replace escaped chars with plain ones
            s = repl_escchars(s)
        }

        docstr = docstr s "\n"

        return 1
    }
    else {
        # no match
        return 0
    }
}

function read_heredocs() {

    # capture a here-doc with leading ': ' at the top of a function definition
    # e.g.
    #   func ()
    #   {
    #       : <<- 'EOF'
    #       Script usage:
    #           myscript [options] argument
    #
    #       Options:
    #           -h, --help Show this message
    #           -f, --foo This option does foo
    #           -b, --bar This option does bar
    #
    #       EOF
    #
    #       echo "func body"
    #       ...
    #   }

    # - capture EOF marker
    #   match: RSTART has start index (from 1), RLENGTH has char length of match
    if ( match($0, /[[:alnum:]_]+/) ) {

        eof_mrkr = substr($0, RSTART, RLENGTH)
    }
    else {
        print "eof_mrkr not found"
        exit 2
    }

    # read until EOF
    getline s

    while ( ! match(s, "^[[:blank:]]*" eof_mrkr "$") ) {

        # string continues
        docstr = docstr s "\n"

        if ( ! getline s ) break
        # print "continuing with <" s ">" > "/dev/stderr" # debug
    }
}

function repl_escchars(s) {

    # replace escaped chars with plain ones
    # - to avoid multiple layers of escapes, octal chars are used for special chars,
    #   e.g. 42 -> ", 134 -> \, 44-> $, 140 -> `, 41 -> !
    gsub(/\134\42/, "\"", s)
    gsub(/\134\134/, "\\", s)
    gsub(/\134\44/, "$", s)
    gsub(/\134\140/, "`", s)
    gsub(/\134\41/, "!", s)

    return s
}

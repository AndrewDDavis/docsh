docsh() {

    [[ $# -gt 0  &&  $1 == @(-h|--help) ]] && {

        : "Print documentation for shell functions and scripts.

        Usage

          docsh [options] [ - | <func-name> | doc-string ...]

        The <doc-string> parameter represents the documentation to be printed, and may
        be a single-line string, a multi-line string, or a series of strings. A series
        of strings will be joined using newlines.

        Single-quoting the doc-string(s) is recommended, unless you need single quotes
        inside them. In this case, double quotes may be used, taking care to escape
        special characters like \\\$ and \\\`. Refer to 'Quoting' in 'man bash'. If the
        argument '-' is given as the doc-string, the doc-string is read from STDIN.

        If a function name is passed as the only positional argument, it is used in the
        same way as with the '-f' option. In this case, the doc-strings are obtained
        from the initial lines of the function definition. These should start with a
        colon (':') followed by and possibly preceded by whitespace , e.g. '    : '. The
        colon command is a null shell command that ignores its arguments and returns
        true. Comments in the function definition are ignored, as they are not printed
        by \`'declare -pf'\`. The doc-strings may be defined over several lines, all
        preceded by a colon, but a single multi-line string is recommended, e.g.:

          : \"this is the first line of the doc-strings

          further details about the function
          that's it, good luck
          \"

        A quoted here-doc could also be used, as in ' : << 'EOF'\\n ...\\nEOF'. In this
        case, the 'EOF' marker may be preceded by any whitespace, whether the here-doc
        is invoked with '<<' or '<<-', and must be followed by a newline.

        TODO (needs testing): As a third option, the doc-strings may be placed in a
        separate file, then referenced from the first line of the function, like
        ' : docsh ./myfile.txt' or ' : cat /path/to/file.md'.

        When printing the docstrings, consistent leading whitespace is removed from
        lines after the first one. This allows the docstring to be indented naturally in
        the source code, and also be well formatted when viewing a function with the
        \`type\` command.

        The return status of \`docsh\` is 0 on successful printing of docstrings,
        otherwise > 0. This may change if a '-t' argument is implemented.

        Options

          -D
          : Render a brief description above the printed docstring. The description is
            drawn from the first line of the doc-string. Commonly used with -T.

          -d <str>
          : Render description as in -D, but use the provided string.

          -f <func-name>
          : Get the doc-strings from the function definition. See formatting notes,
            above.

          -T
          : Render a title above the printed docstring, which is the name of the calling
            function or the function indicated by '-f'. An extra newline is also added
            after the docstring.

        Examples

        Defining the doc-strings using the colon syntax can be nice and simple:

          ex1() {

              : \"This function prints something useful.

              Usage: func1 [options] <arg>

              Note: more docs
              \"

              [[ \$# -eq 0  ||  \$1 == -h ]] && { docsh -TD; return; }

              echo 'something useful'
          }

        To use this style in a function that might be run without docsh available, you
        you can use this block with the test, instead:

              # function docs
              [[ \$# -eq 0  ||  \$1 == -h ]] && {
                  [[ -n \$( command -v docsh ) ]] &&
                      { docsh -TD; return; }

                  declare -pf \"\${FUNCNAME[0]}\" | head -n \$(( \$LINENO - 5 ))
                  return
              }

        On the other hand, defining or passing the doc-strings within a conditional
        block means that they will still be printed when running \`type <func-name>\`,
        but not when debugging the function with '\`set -x\`'. This is especially
        relevant for functions that run with the prompt. To keep this simple, docsh
        supports the 'false && : ...' idiom for the colon line, which can be used like:

              false && : \"This function prints something useful.
              ...
              \"

        TODO: not implemented

          ex4()
          {
              # This general-purpose trap function handles docsh specially in
              # its testing mode:
              trap 'trap-err \$?
                    return' ERR
              trap 'trap - ERR RETURN' RETURN

              docsh -t 0,h -TD \"\$docstr\"

              echo foo
              #...
          }

        Other Notes

        - The motivation for this function comes from wanting simple, Python-style
        docstrings in the shell. This has been expressed by others, e.g. in
        [this QA](https://stackoverflow.com/questions/54949060/standardized-docstring-self-documentation-of-bash-scripts).

        - [This blog post](https://linuxconfig.org/how-to-embed-documentation-in-bash-scripts)
          describes a method of including documentation, using heredocs after the null
          command (:), and using Perl's POD format. I would prefer to support Markdown
          (possibly MyST style).
        "
        docsh -DT
        return
    }

    # TODO:
    #
    # - support markdown in the doc-strings, e.g. headings using ##, links
    #
    # - consider building the test for e.g. '-h' option or 0 args into this command,
    #   so scripts could simply call `docsh -t 0,h "$@" -- '...'` and docsh would either
    #   return 0 or print the usage and return 1; then a return call after the docsh
    #   call would maintain the status
    #
    #   docstr for this:
    #
    #      -t <str>
    #      : Test arguments for conditions. The string argument is a comma-separated list
    #        of tests to perform, e.g. \"0,h\". If any of the tests are true, the
    #        function prints usage and returns false. Tests:
    #        0 : test for 0 arguments
    #
    # - or i could set an error or return trap in the shell, and have it call docsh?
    #
    # - for functions with long docs, it would be better to put the docs in a separate
    #   file, and have a hint in the function body, e.g.:
    #   : to see this functions documentation, issue 'func -h'
    #   the separate file could be e.g. func.docsh within the same directory.


    # return on non-zero exit
    trap '
        trap-err $?
        return
    ' ERR

    trap '
        unset -f _strip_ws
        trap - ERR RETURN
    ' RETURN

    # Parse args
    local flag OPTARG OPTIND=1
    local show_title='' desc doc_tests func_nm

    while getopts ":d:Df:t:T" flag
    do
        case $flag in
            ( d )  desc=$OPTARG ;;
            ( D )  desc=_from_body ;;
            ( f )  func_nm=$OPTARG ;;
            ( T )  show_title=1 ;;
            ( t )  doc_tests=$OPTARG; echo not implemented; return 2 ;;  # TODO
            ( \? ) err_msg 2 "Unknown option: '-$OPTARG'" ;;
            ( : )  err_msg 2 "Missing arg for '-$OPTARG'" ;;
        esac
    done
    shift $(( OPTIND - 1 ))

    # set func_nm if not specified
    [[ -z ${func_nm-} ]] && {

        if [[ $# -eq 1 ]] && grep -q 'function' <<< $( type -at "$1" )
        then
            func_nm=$1
            shift
        else
            func_nm=${FUNCNAME[1]-}
        fi
    }

    _strip_ws() {

        # - strip consistent whitespace from start of lines > 1
        # - ws is null if docs_body is a single line or no leading ws on lines 2+
        local ws _filt

        # capture initial whitespace from first non-blank line
        _filt='
            # ignore line 1
            1 d

            /[^[:blank:]]/ {
                s/^([[:blank:]]*).*/\1/
                p; q
            }
        '

        ws=$( sed -nE "$_filt" <<< "$1" )

        # apply the filter
        sed -E "s/^$ws//" <<< "$1"
    }


    # Get doc-strings from remaining arg(s) or function definition
    local docs_body

    if [[ $# -eq 1  &&  $1 == '-' ]]
    then
        docs_body=$( cat - )
        shift

    elif [[ $# -gt 0 ]]
    then
        # collect all arguments into a string with newlines
        docs_body=$( printf '%s\n' "$@" )
        shift $#

        # vvv old idea
        # use null command to prevent IFS from being set permanently
        # - this appears fragile: only works for $*, not ${arr[*]}, undocumented
        # IFS=$'\n' : docs_body="$*"

    else
        [[ -z $func_nm ]] &&
            err_msg 2 "No func_nm to use for doc-strings"

        # read function definition
        local func_defn
        func_defn=$( declare -pf "$func_nm" ) # | sed '1,2 d; $ d; s/;$//' )

        # parse func defn with awk code found in the same dir as this source file
        local awk_fn
        awk_fn=$( dirname "$( canonpath "${BASH_SOURCE[0]}" )" )/colon_docs.awk
        [[ -r $awk_fn ]] ||
            err_msg 2 "colon_docs.awk not found"

        # The previous _here_docs, _colon_docs, etc. functions have been rewritten in awk
        docs_body=$( awk -f "$awk_fn" -- - <<< "$func_defn" ) \
            || return

        [[ $( wc -l <<< "$docs_body" ) -eq 1 ]] && {

            # check for file reference
            # e.g. ' : docsh ./myfile.txt' or ' : cat /path/to/file.md'
            local _filt _fn
            _filt='
                s/^[[:blank:]]*:[[:blank:]]+(docsh|cat)[[:blank:]]+(.*)$/\2/
                # branch and print on match, otherwise quit
                t h
                q
                : h
                p; d
            '
            _fn=$( sed -nE "$_filt" <<< "$docs_body" )

            [[ -n $_fn  &&  -r $_fn ]] &&
                docs_body=$( cat "$_fn" )
        }
    fi


    # Strip leading whitespace from lines > 1
    # - this allows block indententation in code, but preserves indents within the block
    docs_body=$( _strip_ws "$docs_body" )

    # Get description from line 1 of docs_body, if indicated
    [[ ${desc-} == _from_body ]] &&
    {
        desc=$( sed "1 q" <<< "$docs_body" )
        docs_body=$( sed "1 d" <<< "$docs_body" )
    }

    # Add a bit of leading space to each line, for style
    local lws='  '

    # Import ANSI strings for text styles, if necessary
    [[ -z ${_cbo-}  &&  $( type -t str_csi_vars ) == function ]] &&
        str_csi_vars -d

    # - not using _cbo, as it has prompt ignore chars in it too (like \001),
    #   which messes up 'less' display
    local _bld _dim _ita _uln _rsb _rsd _rsi _rsu _rst
    _bld=$'\e[1m'
    _dim=$'\e[2m'
    _ita=$'\e[3m'
    _uln=$'\e[4m'
    _rsb=$'\e[22m'
    _rsd=$'\e[22m'
    _rsi=$'\e[23m'
    _rsu=$'\e[24m'
    _rst=$'\e[0m'

    # Print header from title and/or description
    if [[ -n $show_title ]]
    then
        [[ -z $func_nm ]] &&
            err_msg 2 "No func_nm to use as title"

        # Stylize title and add extra newlines
        printf '\n%s%s' "$lws" "${_uln}${_bld}$func_nm${_rsb}${_rsu}"

        if [[ -n ${desc-} ]]
        then
            printf ' : %s' "$desc"
        fi

        # newline to finish either title or description
        printf '\n'

        # decided against manually underlining the title
        #printf -- '-%.0s' $(seq $((${#title}+2)))  # auto-underline
        #printf '\n'

        # add an extra newline after the body as well
        docs_body=${docs_body}$'\n'

    elif [[ -n ${desc-} ]]
    then
        # Less newlines with only description
        printf '%s%s\n' "$lws" "$desc"
    fi

    # Print docstring body, with style filters
    local style_filt

    style_filt="# Bold styling for common headings
                s/^((Usage|Option|Command|Example|Note|Notable|Patterns)[^:]*)/${_bld}\1${_rsb}/

                # Dim URLs (regex is a bit naiive)
                s|([a-zA-Z0-9]+://[a-zA-Z0-9@/.?&=-]+)|${_dim}\1${_rsd}|

                # Consider markdown links like [foo](http://bar...), or [foo]: http://...
                # ...

                # Italics for text between \`...\`
                s/(^|[^\`])\`([^\`]+)\`/\1${_ita}\2${_rsi}/g

                # Add leading whitespace, for style
                s/^/$lws/

                # Italics for multi-line text between \`\`\`...\`\`\`
                # - lws must be added whenever we use n
                /^[ \t]*\`\`\`/ {
                    s/\$/${_ita}/
                    : a
                    n
                    s/^/$lws/
                    /^[ \t]*\`\`\`/ { s/^/${_rsi}/; b z; }
                    b a
                    : z
                }
               "

    sed -E "$style_filt" <<< "$docs_body"
}

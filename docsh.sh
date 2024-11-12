docsh()
{
    [[ $# -gt 0  &&  $1 == @(-h|--help) ]] &&
    {
        docsh -DT "Print documentation for shell functions and scripts.

        Usage

          docsh [options] [ - | doc-string ...]

        The <doc-string> parameter represents the documentation to be printed, and may
        be a single-line string, a multi-line string, or a series of strings. A series
        of strings will be joined using newlines.

        Single-quoting the doc-string(s) is recommended, unless you need single quotes
        inside them. In this case, double quotes may be used, taking care to escape
        special characters like \\\$ and \\\`. Refer to 'Quoting' in 'man bash'. If the
        argument '-' is given as the doc-string, the doc-string is read from STDIN.

        When printing the docstrings, consistent leading whitespace on lines after the
        first one is removed. This allows the docstring to be indented naturally in
        the source code, and also be well formatted when viewing a function with the
        \`type\` command.

        When using the '-f' option to get the doc-strings from the function, the
        function should have its initial lines starting with whitespace and colons, e.g.
        '    : '. For very simple docs, you can use multiple colon lines, but for more
        complex docs, which may contain '<' or '$', use a quoted here-doc, e.g.:

             : << 'EOF'
            this is a
            long string that
            documents the <func> \$abc
            EOF

        The 'EOF' marker may be preceded by any whitespace, whether the here-doc is
        invoked with '<<' or '<<-', and must be followed by a newline.

        TODO: As a third option, the doc-strings may be placed in a separate file, then
        referenced from the first line of the function, like ' : docsh ./myfile.txt' or
        ' : cat /path/to/file.md'.

        Options

          -D
          : Render a brief description above the printed docstring. The description is
            drawn from the first line of the doc-string. Commonly used with -T.

          -d <str>
          : Render description as in -D, but use the provided string.

          -T
          : Render a title above the printed docstring, which is obtained from the name
            of the calling function. An extra newline is also added to the end of the
            docstring.

          -f <func-name>
          : Get the documentation from the function definition. See formatting notes,
            above.

        Examples

          func1()
          {
              # It is recommended to define the docstr within a conditional block or
              # function, so that it still gets printed when running \`type func1\`, but
              # not when runnning the function with '\`set -x\`'. If using a function, it
              # is good practice to '\`unset -f\`' it with a return trap.

              [[ \$# -eq 0  ||  \$1 == @(-h|--help) ]] &&
              {
                  docsh -TD \"This function prints something useful.

                  Usage: func1 [options] <arg>

                  This long multi-line string
                  documents the function.
                  \"
                  return 0
              }

              echo 'something useful'
          }

          func2()
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

        The return status of docsh is 0 on successful printing of docstrings, otherwise > 0. This may change if a '-t' argument is implemented.

        Other Notes

        - The motivation for this function comes from wanting simple, Python-style
        docstrings as expressed by others in this QA:
          https://stackoverflow.com/questions/54949060/standardized-docstring-self-documentation-of-bash-scripts

        - Here is a blog post that describes a method of including documentation, using
          heredocs after the null command (:), and using Perl's POD format. Myself, I
          would prefer markdown (possibly Myst style).
          https://linuxconfig.org/how-to-embed-documentation-in-bash-scripts

        "
        return 0
    }

    # TODO:
    #
    # - consider building the test for e.g. '-h' option or 0 args into this command,
    #   so scripts could simply call `docsh -t 0,h "$@" '...'` and docsh would either
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
    trap 'trap-err $?
          return' ERR

    trap 'trap - ERR RETURN
          unset -f _colon_docs _here_docs _strip_ws' RETURN

    # Parse args
    local OPT OPTARG OPTIND=1
    local title desc doc_tests from_func

    while getopts "d:Df:t:T" OPT
    do
        case $OPT in
            ( d )  desc=$OPTARG ;;
            ( D )  desc=_from_body ;;
            ( f )  from_func=$OPTARG ;;
            ( T )  title=${FUNCNAME[1]} ;;
            ( t )  doc_tests=$OPTARG; echo not implemented ;;  # TODO
            ( ? )  err_msg 1 "Args: $*" ;;
        esac
    done
    shift $(( OPTIND - 1 ))


    _colon_docs()
    {
        # print any lines with leading ': ' at the top of the function definition
        # e.g.
        #   func ()
        #   {
        #       : this is
        #       : the docstring
        #       : of the function
        #   }

        local _filt

        _filt='
            # ignore first 2 lines
            1,2 d

            # print next matching lines without the leading chars or last semicolons
            /^[[:blank:]]*:[[:blank:]]?/ {
                s/^[[:blank:]]*:[[:blank:]]?//
                s/;$//
                p; d; }

            # quit on first non-matching line
            q
        '
        declare -pf "$1" | sed -nE "$_filt"
    }

    _here_docs()
    {
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

        local _filt mrkr ln

        # capture EOF marker and line no. of here-doc start
        _filt="
            # ignore first 2 lines
            1,2 d

            # test for here-doc start
            s/^[[:blank:]]*:[[:blank:]]*<<-?[[:blank:]]?['\"]?([[:alnum:]]+)['\"]?$/\1/
            t h

            # quit on fail
            q

            # print the here-doc EOF marker and line number
            : h
            p; =; q
        "
        read -r -d '' mrkr ln < <( declare -pf "$1" | sed -nE "$_filt" )

        # print here-doc, if any
        [[ -z $mrkr ]] ||
        {
            _filt="$ln,/^[[:blank:]]*$mrkr$/ { p; d; }"

            declare -pf "$1" | sed -nE "$_filt" | sed '1 d; $ d;'
        }
    }

    _strip_ws()
    {
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

    [[ $# -eq 0 ]] && from_func=${FUNCNAME[1]}

    if [[ -n "$from_func" ]]
    then
        docs_body=$( _here_docs "$from_func" )

        [[ -n $docs_body ]] ||
            docs_body=$( _colon_docs "$from_func" )

        if [[ $( wc -l <<< "$docs_body" ) -eq 1 ]]
        then
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
            {
                docs_body=$( cat "$_fn" )
            }
        fi

    elif [[ $1 == '-' ]]
    then
        docs_body=$( cat - )
        shift

    else
        IFS=$'\n' docs_body="$*"
        shift $#
    fi


    # Strip leading whitespace from lines > 1
    # - this allows block indententation in code, but preserves indents within the block
    docs_body=$( _strip_ws "$docs_body" )

    # Get description from line 1 of docs_body, if indicated
    [[ ${desc:-} == _from_body ]] &&
    {
        desc=$( sed "1 q" <<< "$docs_body" )
        docs_body=$( sed "1 d" <<< "$docs_body" )
    }

    # Add a bit of leading space to each line, for style
    local lws='  '

    # Import ANSI strings for text styles, if necessary
    [[ -z ${_cbo:-}  &&  $( type -t csi_strs ) == function ]] &&
        csi_strs -d

    # Print header from title and/or description
    if [[ -n ${title:-} ]]
    then
        # Stylize title and add extra newlines
        printf '\n%s%s' "$lws" "${_cul:-}${_cbo:-}$title${_crb:-}${_cru:-}"

        if [[ -n ${desc:-} ]]
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

    elif [[ -n ${desc:-} ]]
    then
        # Less newlines with only description
        printf '%s%s\n' "$lws" "$desc"
    fi

    # Print docstring body, with style filters
    local style_filt

    style_filt="# Bold styling for common headings
                s/^((Usage|Option|Command|Example|Note|Notable|Patterns)[^:]*)/${_cbo:-}\1${_crb:-}/

                # Dim URLs (regex is a bit naiive)
                s|([a-zA-Z0-9]+://[a-zA-Z0-9@/.?&=-]+)|${_cdm}\1${_crd}|

                # Consider markdown links like [foo](http://bar...), or [foo]: http://...
                # ...

                # Italics for text between \`...\`
                s/(^|[^\`])\`([^\`]+)\`/\1${_cit:-}\2${_cri:-}/g

                # Add leading whitespace, for style
                s/^/$lws/

                # Italics for multi-line text between \`\`\`...\`\`\`
                # - lws must be added whenever we use n
                /^[ \t]*\`\`\`/ {
                    s/\$/${_cit:-}/
                    : a
                    n
                    s/^/$lws/
                    /^[ \t]*\`\`\`/ { s/^/${_cri:-}/; b z; }
                    b a
                    : z
                }
               "

    sed -E "$style_filt" <<< "$docs_body"
}

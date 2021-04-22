# GNU Awk program for torrents categorization.
# Author: David Pi
# Requires: gawk 4+
#
# variable assignment (-v var=val):
#   regexfile
# standard input:
#   path \0 size \0 ...
# standard output:
#   {"default", "av", "film", "tv", "music"}

BEGIN {
    RS = "\0"
    raise_exit = size_reached = 0
    size_thresh = 52428800  # 50 MiB
    delete sizedict

    if (regexfile != "" && (getline av_regex < regexfile) > 0 && av_regex ~ /[^[:space:]]/) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", av_regex)
    } else {
        raise("Reading regexfile '" regexfile "' failed.")
    }
    close(regexfile)
}

FNR % 2 {  # path
    path = $0
    next
}

path == "" || ! /^[0-9]+$/ {
    printf("[AWK] Record ignored: ('%s', '%s')\n", path, $0) > "/dev/stderr"
    next
}

{   # size
    if ($0 >= size_thresh) {
        if (! size_reached) {
            delete sizedict
            size_reached = 1
        }
    } else if (size_reached) {
        next
    }
    path = tolower(path)
    if (path ~ /m2ts$/) {
        sub(/\/bdmv\/stream\/[^/]+\.m2ts$/, "/bdmv.m2ts", path)
    } else if (path ~ /vob$/) {
        sub(/\/[^/]*vts[0-9_]+\.vob$/, "/video_ts.vob", path)
    }
    sizedict[path] += $0  # {path: size}
}

END {
    if (raise_exit)
        exit 1
    if (! length(sizedict))
        raise("Invalid input. Expect null-terminated (path, size) pairs.")

    type = pattern_match(sizedict, videoset)
    if (type == "film" && length(videoset) >= 3)
        series_match(videoset)
    output(type)
}


function raise(msg)
{
    printf("[AWK] Error: %s\n", msg) > "/dev/stderr"
    raise_exit = 1
    exit 1
}

function output(type)
{
    # if (type !~ /^(default|av|film|tv|music)$/)
    #     raise("Invalid type: " type)
    print type
    exit 0
}

# Split the path into a pair (root, ext). This behaves the same way as Python's
# os.path.splitext, except that the period between root and ext is omitted.
function splitext(p, pair,  s, i, isext)
{
    delete pair
    s = p
    while (i = index(s, "/"))
        s = substr(s, i + 1)
    while (i = index(s, ".")) {
        s = substr(s, i + 1)
        if (i > 1) isext = 1
    }
    if (isext) {
        pair[1] = substr(p, 1, length(p) - length(s) - 1)
        pair[2] = s
    } else {
        pair[1] = p
        pair[2] = ""
    }
}

# match files against patterns
# save video files to: videoset[root]
# return the most significant file type
function pattern_match(sizedict, videoset,  p, a, type, arr)
{
    delete videoset
    PROCINFO["sorted_in"] = "@val_num_desc"
    for (p in sizedict) {
        splitext(p, a)
        switch (a[2]) {
        case "iso":
            if (a[1] ~ /(\y|_)(adobe|microsoft|windows|v[0-9]+(\.[0-9]+)+|x(64|86))(\y|_)/) {
                type = "default"
                break
            }
            # fall-through to video
        case /^((fl|og|vi|yu)v|3g[2p]|[as]vi|[aw]mv|asf|divx|f4[abpv]|hevc|m(2?ts|4p|[24kop]v|p[24e]|pe?g|xf)|qt|rm|rmvb|swf|ts|vob|webm)$/:
            if (a[1] ~ av_regex)
                output("av")
            if (a[1] ~ /(\y|_)([es]|ep[ _-]?|s([1-9][0-9]|0?[1-9])e)([1-9][0-9]|0?[1-9])(\y|_)/)
                output("tv")
            videoset[a[1]]
            type = "film"
            break
        case /^((al?|fl)ac|(m4|og|r|wm)a|aiff|ape|m?ogg|mp[3c]|opus|pcm|wa?v)$/:
            type = "music"
            break
        default:
            type = "default"
        }
        arr[type] += sizedict[p]
    }
    for (type in arr) break
    delete PROCINFO["sorted_in"]
    return type
}

# Scan videoset to identify consecutive digits.
# input:
#   videoset[path/a_05]
#   videoset[path/a_06]
#   videoset[path/a_04a_05]
# After split, grouped as:
#   arr[1, "a"][5]
#   arr[1, "a"][6]
#   arr[1, "a"][4]
#   arr[2, "a"][5]
#   (one file would never appear in the same group twice)
# For each group, sort its sub-array by keys. arr[1, "a"] become:
#   nums[1] = 4
#   nums[2] = 5
#   nums[3] = 6
# If we found three consecutive digits in one group, identify as TV Series.
function series_match(videoset,  m, n, i, words, nums, arr)
{
    for (m in videoset) {
        n = split(m, words, /[0-9]+/, nums)
        for (i = 1; i < n; i++) {
            gsub(/.*\/|[[:space:][:punct:]]+/, "", words[i])
            arr[i, words[i]][nums[i] + 0]
        }
    }
    for (m in arr) {
        if (length(arr[m]) < 3) continue
        n = asorti(arr[m], nums, "@ind_num_asc") - 2
        for (i = 1; i <= n; i++) {
            if (nums[i] + 2 == nums[i + 2])
                output("tv")
        }
    }
}

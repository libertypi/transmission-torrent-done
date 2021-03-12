# GNU Awk program for torrents categorization.
# Author: David Pi
#
# input stream:
#   path \0 size \0 ...
# variable assignment (passed via "-v"):
#   regexfile="/path/to/regexfile"
# output is one of:
#   default, av, film, tv, music

BEGIN {
    if (PROCINFO["version"] < 4)
        raise("GNU Awk >= 4 required.")

    RS = "\000"
    delete sizedict
    raise_exit = size_reached = 0
    size_thresh = (50 * 1024 ^ 2)  # "soft" thresh: 50 MiB

    if (regexfile != "" && (getline av_regex < regexfile) > 0 && av_regex ~ /[^[:space:]]/) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", av_regex)
    } else {
        raise("Reading regexfile '" regexfile "' failed.")
    }
    close(regexfile)
}

NR % 2 {
    path = $0
    next
}

# sizedict[path]: size
/^[0-9]*$/ {
    if ($0 >= size_thresh) {
        if (! size_reached) {
            delete sizedict
            size_reached = 1
        }
    } else if (size_reached) {
        next
    }
    path = tolower(path)
    sub(/\/bdmv\/stream\/[^/]+\.m2ts$/, "/bdmv/index.bdmv", path) ||
    sub(/\/video_ts\/[^/]+\.vob$/, "/video_ts/video_ts.vob", path)
    sizedict[path] += $0
}

END {
    if (raise_exit)
        exit 1
    if (NR % 2 || ! length(sizedict))
        raise("Invalid input. Expect null-terminated (path, size) pairs.")

    type = cat_type(sizedict, videolist)
    if (type == "video")
        type = cat_video(videolist)
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
    if (type ~ /^(default|av|film|tv|music)$/) {
        print type
        exit 0
    } else {
        raise("Invalid type: " type)
    }
}

# categorize file types
# save videos to: videolist[1]: path ...
# returns: the most significant type
function cat_type(sizedict, videolist,  i, j, type, arr)
{
    delete videolist
    PROCINFO["sorted_in"] = "@val_num_desc"
    for (i in sizedict) {
        switch (i) {
        case /\.iso$/:
            if (i ~ /(\y|_)(v[0-9]+(\.[0-9]+)+|x(64|86)|adobe|microsoft|windows)(\y|_)/) {
                type = "default"
                break
            }
            # fall-through to video
        case /\.((a|bd|w)mv|(fl|og|vi|yu)v|3g[2p]|[as]vi|asf|f4[abpv]|m(2?ts|4p|[24kop]v|p[24g]|peg?|xf)|qt|rm|rmvb|ts|vob|webm)$/:
            videolist[++j] = i
            type = "video"
            break
        case /\.((al?|fl)ac|(m4|og|r|wm)a|aiff|ape|m?ogg|mp[3c]|opus|wa?v)$/:
            type = "music"
            break
        default:
            type = "default"
        }
        arr[type] += sizedict[i]
    }
    for (type in arr) break
    delete PROCINFO["sorted_in"]
    return type
}

# categorize videos
function cat_video(videolist,  n, i)
{
    n = length(videolist)
    for (i = 1; i <= n; i++) {
        if (videolist[i] ~ av_regex)
            return "av"
        if (videolist[i] ~ /(\y|_)([es]|ep[ _-]?|s([1-9][0-9]|0?[1-9])e)([1-9][0-9]|0?[1-9])(\y|_)/)
            return "tv"
    }
    if (n >= 3 && match_series(videolist)) {
        return "tv"
    } else {
        return "film"
    }
}

# Scan videolist to identify consecutive digits:
# input:
#   videolist[1]: "parent/string_05.mp4"
#   videolist[2]: "parent/string_06.mp4"
#   videolist[3]: "parent/string_04string_05.mp4"
# grouped as:
#   arr[1, "string"][5] (parent/string_05.mp4)
#   arr[1, "string"][6] (parent/string_06.mp4)
#   arr[1, "string"][4] (parent/string_04string_05.mp4)
#   arr[2, "string"][5] (parent/string_04string_05.mp4)
#   (one file would never appear in the same group twice)
# for each group, sort its subgroups by keys:
#   nums[1]: 4
#   nums[2]: 5
#   nums[3]: 6
# if we found three consecutive digits in one group, return true.
function match_series(videolist,  m, n, i, j, words, nums, arr)
{
    for (m in videolist) {
        n = split(videolist[m], words, /[0-9]+/, nums)
        for (i = 1; i < n; i++) {
            gsub(/.*\/|[[:space:][:punct:]]+/, "", words[i])
            arr[i, words[i]][nums[i] + 0]
        }
    }
    for (m in arr) {
        if (length(arr[m]) < 3) continue
        n = asorti(arr[m], nums, "@ind_num_asc")
        i = 1
        for (j = 2; j <= n; j++) {
            if (nums[j - 1] == nums[j] - 1) {
                if (++i == 3) return 1
            } else {
                i = 1
            }
        }
    }
    return 0
}

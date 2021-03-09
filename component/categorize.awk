# GNU Awk program for torrents categorization.
# Author: David Pi
#
# Input stream:
#   size\0path\0, ...
# Variable assignment (passed via "-v"):
#   regexfile=/path/to/regexfile
# Output is one of:
#   default, av, film, tv, music

BEGIN {
    RS = "^$"
    if (regexfile != "" && (getline av_regex < regexfile) > 0 && av_regex ~ /\S/) {
        gsub(/^\s+|\s+$/, "", av_regex)
    } else {
        raise("Reading regexfile '" regexfile "' failed.")
    }
    close(regexfile)
    RS = "\000"
    raise_exit = size_reached = 0
    size_thresh = (80 * 1024 ^ 2)
    split("", sizedict)
    split("", typedict)
    split("", videoset)
}

NR % 2 {
    if ($0 !~ /^[0-9]+$/)
        raise("Invalid size, expect integer: '" $0 "'")
    size = $0
    next
}

# sizedict[path]: size
{
    if (size >= size_thresh) {
        if (! size_reached) {
            delete sizedict
            size_reached = 1
        }
    } else if (size_reached) {
        next
    }
    path = tolower($0)
    sub(/\/bdmv\/stream\/[^/]+\.m2ts$/, "/bdmv/index.bdmv", path) ||
    sub(/\/video_ts\/[^/]+\.vob$/, "/video_ts/video_ts.vob", path)
    sizedict[path] += size
}

END {
    if (raise_exit)
        exit 1
    if (NR % 2)
        raise("Invalid input. Expect null-terminated (size, path) pairs.")
    if (! length(sizedict))
        raise("Empty input.")

    pattern_match(sizedict, typedict, videoset)
    if (length(videoset) >= 3)
        series_match(videoset)

    PROCINFO["sorted_in"] = "@val_num_desc"
    for (i in typedict) output(i)
}


function raise(msg)
{
    printf("[AWK] Fatal: %s\n", msg) > "/dev/stderr"
    raise_exit = 1
    exit 1
}

# match files against patterns
# save video files to: videoset[path]
# save cumulative size to: typedict[type]: sum
function pattern_match(sizedict, typedict, videoset,  i, type)
{
    delete typedict
    delete videoset
    PROCINFO["sorted_in"] = "@val_num_desc"
    for (i in sizedict) {
        switch (i) {
        case /\.((a|bd|w)mv|3g[2p]|[as]vi|asf|f4[abpv]|flv|iso|m(2?ts|4p|[24kop]v|p[24e]|pe?g|xf)|og[gv]|qt|rm|rmvb|ts|viv|vob|webm|yuv)$/:
            if (i ~ av_regex)
                output("av")
            if (i ~ /\y([es]|ep[ _-]?|s([1-9][0-9]|0?[1-9])e)([1-9][0-9]|0?[1-9])\y/)
                output("tv")
            videoset[i]
            type = "film"
            break
        case /\.((al?|fl)ac|ape|m4a|mp3|ogg|wav|wma)$/:
            type = "music"
            break
        default:
            type = "default"
        }
        typedict[type] += sizedict[i]
    }
    delete PROCINFO["sorted_in"]
}

# Scan videoset to identify consecutive digits:
# input:
#   videoset[parent/string_05.mp4]
#   videoset[parent/string_06.mp4]
#   videoset[parent/string_04string_05.mp4]
# After split, grouped as:
#   groups[1, "string"][5] (parent/string_05.mp4)
#   groups[1, "string"][6] (parent/string_06.mp4)
#   groups[1, "string"][4] (parent/string_04string_05.mp4)
#   groups[2, "string"][5] (parent/string_04string_05.mp4)
#   (file would never appear in one group twice)
# For each group, sort its subgroup by the digits:
#   nums[1] = 4
#   nums[2] = 5
#   nums[3] = 6
# If we found three consecutive digits in one group,
# identify as TV Series.
function series_match(videoset,  m, n, i, j, words, nums, groups)
{
    for (m in videoset) {
        n = split(m, words, /[0-9]+/, nums)
        for (i = 1; i < n; i++) {
            gsub(/.*\/|\s+/, "", words[i])
            groups[i, words[i]][int(nums[i])]
        }
    }
    for (m in groups) {
        if (length(groups[m]) < 3) continue
        n = asorti(groups[m], nums, "@ind_num_asc")
        i = 1
        for (j = 2; j <= n; j++) {
            if (nums[j - 1] == nums[j] - 1) {
                if (++i == 3) output("tv")
            } else {
                i = 1
            }
        }
    }
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

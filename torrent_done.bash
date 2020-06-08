#!/usr/bin/env bash

export LC_ALL=C LANG=C

seed_dir='/volume2/@transmission'
watch_dir='/volume1/video/Torrents'
script_dir="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)"
log_file="${script_dir}/log.log"
av_regex="${script_dir}/component/av_regex.txt"
tr_api='http://localhost:9091/transmission/rpc'

case "$1" in
  'debug' | '-d' | '-debug') debug=1 ;;
  *) debug=0 ;;
esac
readonly debug

prepare() {
  printf '[DEBUG] %s' "Acquiring lock..." 1>&2
  exec {i}<"${BASH_SOURCE[0]}"
  flock -x "${i}"
  printf '%s\n' 'Done.' 1>&2
  trap 'write_log' EXIT
}

append_log() {
  printf -v "logs[${#logs[@]}]" '%-20(%D %T)T%-10s%-35s%s' '-1' "$1" "${2:0:33}" "${3}"
}

write_log() {
  if ((${#logs[@]} > 0)); then
    printf '[DEBUG] Logs: (%s entries)\n' "${#logs[@]}" 1>&2
    printf '%s\n' "${logs[@]}" 1>&2
    if ((debug == 0)); then
      local log_bak
      [[ -s ${log_file} ]] && log_bak="$(tail -n +3 "${log_file}")"
      {
        printf '%-20s%-10s%-35s%s\n%s\n' \
          'Date' 'Status' 'Destination' 'Name' \
          '-------------------------------------------------------------------------------'
        for ((i = ${#logs[@]} - 1; i >= 0; i--)); do
          printf '%s\n' "${logs[i]}"
        done
        [[ -n ${log_bak} ]] && printf '%s\n' "${log_bak}"
      } >"${log_file}"
    fi
  fi
}

get_tr_api_header() {
  if [[ "$(curl -sI "${tr_api}")" =~ 'X-Transmission-Session-Id:'[[:space:]]+[A-Za-z0-9]+ ]]; then
    tr_session_header="${BASH_REMATCH[0]}"
    printf '[DEBUG] API Header: "%s"\n' "${tr_session_header}" 1>&2
  fi
}

query_tr_api() {
  for i in {1..4}; do
    if curl -sf --header "${tr_session_header}" "${tr_api}" -d "$@"; then
      printf '[DEBUG] Querying API success. Query: "%s"\n' "$*" 1>&2
      return 0
    elif ((i < 4)); then
      printf '[DEBUG] Querying API failed. Retries: %s\n' "${i}" 1>&2
      get_tr_api_header
    else
      printf '[DEBUG] Querying API failed. Query: "%s"\n' "$*" 1>&2
      return 1
    fi
  done
}

get_tr_info() {
  if tr_info="$(query_tr_api '{"arguments":{"fields":["activityDate","percentDone","id","sizeWhenDone","name"]},"method":"torrent-get"}')" &&
    [[ ${tr_info} =~ '"result":'[[:space:]]*'"success"' ]] &&
    tr_stats="$(query_tr_api '{"method":"session-stats"}')" &&
    [[ ${tr_stats} =~ '"torrentCount":'[[:space:]]*([0-9]+) ]] && tr_torrentCount="${BASH_REMATCH[1]}" &&
    [[ ${tr_stats} =~ '"pausedTorrentCount":'[[:space:]]*([0-9]+) ]] && tr_pausedTorrentCount="${BASH_REMATCH[1]}"; then
    printf '[DEBUG] %s\n' "Getting torrents info success." 1>&2
  else
    printf '[DEBUG] Getting torrents info failed. Response: "%s"\n"%s"\n' "${tr_info}" "${tr_stats}" 1>&2
    exit 1
  fi
}

resume_tr_torrent() {
  ((tr_pausedTorrentCount > 0)) && query_tr_api '{"method":"torrent-start"}' >/dev/null
}

handle_torrent_done() {
  [[ -n ${TR_TORRENT_DIR} && -n ${TR_TORRENT_NAME} ]] || return
  [[ -e "${TR_TORRENT_DIR}/${TR_TORRENT_NAME}" ]] || {
    append_log "Missing" "${TR_TORRENT_DIR}" "${TR_TORRENT_NAME}"
    return
  }

  local file_list is_directory destination dest_display

  if [[ ${TR_TORRENT_DIR} == "${seed_dir}" ]]; then

    if [[ -d "${TR_TORRENT_DIR}/${TR_TORRENT_NAME}" ]]; then
      file_list="$(cd "${TR_TORRENT_DIR}" && find "${TR_TORRENT_NAME}" -not -path '*/[@#.]*' -size +50M)"
      [[ -z ${file_list} ]] && file_list="$(cd "${TR_TORRENT_DIR}" && find "${TR_TORRENT_NAME}" -not -path '*/[@#.]*')"
      file_list="${file_list,,}"
      is_directory=1
    else
      file_list="${TR_TORRENT_NAME,,}"
      is_directory=0
    fi

    if grep -Eqf "${av_regex}" <<<"${file_list}"; then
      destination='/volume1/driver/Temp'

    elif [[ ${file_list} =~ [^a-z0-9]([se][0-9]{1,2}|s[0-9]{1,2}e[0-9]{1,2}|ep[[:space:]_-]?[0-9]{1,3})[^a-z0-9] ]]; then
      destination='/volume1/video/TV Series'

    elif [[ ${TR_TORRENT_NAME,,} =~ (^|[^a-z0-9])(acrobat|adobe|animate|audition|dreamweaver|illustrator|incopy|indesign|lightroom|photoshop|prelude|premiere)([^a-z0-9]|$) ]]; then
      destination='/volume1/homes/admin/Download/Adobe'

    elif [[ ${TR_TORRENT_NAME,,} =~ (^|[^a-z0-9])(windows|mac(os)?|x(86|64)|(32|64)bit|v[0-9]+\.[0-9]+)([^a-z0-9]|$)|\.(zip|rar|exe|7z|dmg|pkg)$ ]]; then
      destination='/volume1/homes/admin/Download'

    else
      destination='/volume1/video/Films'
    fi

    dest_display="${destination}"
    ((is_directory)) || destination="${destination}/${TR_TORRENT_NAME%.*}"
    [[ -d ${destination} ]] || mkdir -p "${destination}"

    if cp -rf "${TR_TORRENT_DIR}/${TR_TORRENT_NAME}" "${destination}/"; then
      append_log "Finish" "${dest_display}" "${TR_TORRENT_NAME}"
    else
      append_log "Error" "${dest_display}" "${TR_TORRENT_NAME}"
    fi

  else

    if cp -rf "${TR_TORRENT_DIR}/${TR_TORRENT_NAME}" "${seed_dir}/"; then
      append_log "Finish" "${TR_TORRENT_DIR}" "${TR_TORRENT_NAME}"
      query_tr_api "{\"arguments\":{\"ids\":[${TR_TORRENT_ID}],\"location\":\"${seed_dir}/\"},\"method\":\"torrent-set-location\"}"
    else
      append_log "Error" "${TR_TORRENT_DIR}" "${TR_TORRENT_NAME}"
    fi

  fi
}

clean_local_disk() {
  local obsolete pwd_bak="$PWD"
  shopt -s nullglob dotglob globstar

  if cd "${seed_dir}"; then
    declare -A dict
    while IFS= read -r -d '' i; do
      [[ -n ${i} ]] && dict["${i}"]=1
    done < <(read_tr_info 'name' <<<"${tr_info}")

    if ((${#dict[@]} == tr_torrentCount)); then
      printf '[DEBUG] Torrent dict length match with API response: %d\n' "${tr_torrentCount}" 1>&2
    else
      printf '[DEBUG] Torrent dict length unmatch. API: %d, Dict: %d\n' "${tr_torrentCount}" "${#dict[@]}" 1>&2
      exit 1
    fi

    for i in [^.\#@]*; do
      [[ -n ${dict["${i}"]} ]] || {
        append_log 'Cleanup' "${seed_dir}" "${i}"
        obsolete+=("${seed_dir}/${i}")
      }
    done
  fi

  if cd "${watch_dir}"; then
    for i in **; do
      [[ -s ${i} ]] || obsolete+=("${watch_dir}/${i}")
    done
  fi

  if ((${#obsolete[@]} > 0)); then
    printf '[DEBUG] %s\n' 'Cleanup local disk:' "${obsolete[@]}" 1>&2
    ((debug == 0)) && rm -rf -- "${obsolete[@]}"
  fi

  shopt -u nullglob dotglob globstar
  cd "${pwd_bak}"
}

clean_inactive_feed() {
  local ids names space_to_free free_space

  # Size unit from df: 1024 bytes
  for i in _ free_space; do
    read -r "$i"
  done < <(df --output=avail "${seed_dir}")

  if [[ -z ${free_space} ]]; then
    printf '[DEBUG] %s\n' 'Read disk stats failed.' 1>&2
    return
  elif (((space_to_free = 50 * (1024 ** 3) - (free_space *= 1024)) > 0)); then
    printf '[DEBUG] Cleanup inactive feeds. Disk free space: %s. Space to free: %s.\n' "${free_space}" "${space_to_free}" 1>&2
  else
    printf '[DEBUG] Space enough, skip action. Disk free space: %s\n' "${free_space}" 1>&2
    return
  fi

  while IFS='/' read -r -d '' id size name; do
    [[ -z ${name} ]] && continue
    ids+=("${id}")
    names+=("${name}")

    if (((space_to_free -= size) < 0)); then
      printf '[DEBUG] %s\n' 'Remove torrents:' "${names[@]}" 1>&2
      ((debug == 1)) || {
        printf -v ids '%s,' "${ids[@]}"
        query_tr_api "{\"arguments\":{\"ids\":[${ids%,}],\"delete-local-data\":\"true\"},\"method\":\"torrent-remove\"}"
      } && {
        for name in "${names[@]}"; do
          append_log "Remove" "${seed_dir}" "${name}"
        done
      }
      break
    fi
  done < <(read_tr_info <<<"${tr_info}")
}

# read_tr_info <output:(*|name)>
if hash jq 1>/dev/null 2>&1; then
  printf '[DEBUG] %s\n' 'Using jq to parse json.' 1>&2
  read_tr_info() {
    case "$1" in
      'name')
        jq -j '.arguments.torrents[]|"\(.name)\u0000"'
        ;;
      *)
        jq -j '
          .arguments.torrents |
          sort_by(.activityDate)[] |
          select(.percentDone == 1) |
          "\(.id)/\(.sizeWhenDone)/\(.name)\u0000"
        '
        ;;
    esac
  }
else
  printf '[DEBUG] %s\n' 'Using awk to parse json.' 1>&2
  read_tr_info() {
    awk -v output="$1" '
      BEGIN { RS = "^$"; ORS = "\000" }

      {
        patsplit($0, dicts, /\{[^{}]*"id"[^{}]+"name"[^{}]+\}/)
        for (i in dicts) {
          if (output == "name") {
            if (match(dicts[i], /"name":[[:space:]]*"([^"]+)"/, m)) {
              print m[1]
            }
          } else {
            # This pattern will not match bool: "xxx":true
            while (match(dicts[i], /"([A-Za-z]+)":[[:space:]]*([0-9]+|"([^"]+)")/, m)) {
              if (3 in m) {
                tmp[m[1]] = m[3]
              } else {
                tmp[m[1]] = m[2]
              }
              dicts[i] = substr(dicts[i], RSTART + RLENGTH)
            }
            if (tmp["percentDone"] == 1) {
              result[tmp["id"] "/" tmp["sizeWhenDone"] "/" tmp["name"]] = tmp["activityDate"]
            }
            delete tmp
          }
        }
      }

      END {
        if (output == "name") exit
        PROCINFO["sorted_in"] = "@val_num_asc"
        for (i in result) print i
      }
    ' <(LC_ALL=en_US.UTF-8 printf '%b' "$(</dev/stdin)")
  }
fi

# Main
prepare
get_tr_api_header

handle_torrent_done

get_tr_info
clean_local_disk
clean_inactive_feed

resume_tr_torrent
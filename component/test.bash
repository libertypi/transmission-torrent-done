#!/usr/bin/env bash

export LC_ALL=C LANG=C

categorize='categorize.awk'
regex_file='regex.txt'
video_dir='/volume1/video'
tv_dir="${video_dir}/TV Series"
film_dir="${video_dir}/Films"
driver_dir='/volume1/driver'
av_dir="${driver_dir}/Temp"
seed_dir='/volume2/@transmission'

test_regex() {
  printf '%s\n' "Testing '${regex_file}' on '${driver_dir}'..." "Unmatched items:"
  grep -Eivf "${regex_file}" <(
    find "${driver_dir}" -type f -not -path '*/[.@#]*' -regextype 'posix-extended' \
      -iregex '.+\.((bd|w)mv|3gp|asf|avi|flv|iso|m(2?ts|4p|[24kop]v|p([24]|e?g)|xf)|rm(vb)?|ts|vob|webm)' \
      -printf '%P\n'
  )

  printf '%s' "Testing '${regex_file}' on '${video_dir}'..."
  local result="$(
    grep -Eif "${regex_file}" <(
      find "${video_dir}" -type f -not -path '*/[.@#]*' -printf '%P\n'
    )
  )"
  if [[ -n "${result}" ]]; then
    printf '%s\n' "Failed. Match:" "${result}"
  else
    printf '%s\n' "Passed."
  fi
}

print_help() {
  cat <<EOF 1>&2
usage: ${BASH_SOURCE[0]} [-h] [-t] [-f] [-d DIR] [-r]

Test ${categorize}.
If no argument was passed, test '${seed_dir}'.

optional arguments:
  -h            display this help text and exit
  -t            test '${tv_dir}'
  -f            test '${film_dir}'
  -d DIR        test DIR
  -r            test '${regex_file}' on '${driver_dir}'
EOF
}

cd "${BASH_SOURCE[0]%/*}" || exit 1
TR_TORRENT_DIR="${seed_dir}"
unset names error

while getopts 'htfd:r' a; do
  case "$a" in
    t) TR_TORRENT_DIR="${tv_dir}" ;;
    f) TR_TORRENT_DIR="${film_dir}" ;;
    d)
      TR_TORRENT_DIR="${OPTARG%/*}"
      names=("${OPTARG##*/}")
      ;;
    r)
      test_regex
      exit 0
      ;;
    h)
      print_help
      exit 1
      ;;
    *) exit 1 ;;
  esac
done

((${#names[@]})) || {
  pushd "${TR_TORRENT_DIR}" >/dev/null && names=([^@\#.]*) || exit 1
  popd >/dev/null
}

printf '%s\n\n' "Testing: ${TR_TORRENT_DIR}"

for TR_TORRENT_NAME in "${names[@]}"; do

  printf '%s\n' "${TR_TORRENT_NAME}"

  for i in dest root; do
    IFS= read -r -d '' "$i"
  done < <(
    awk -v REGEX_FILE="${regex_file}" \
      -v TR_TORRENT_DIR="${TR_TORRENT_DIR}" \
      -v TR_TORRENT_NAME="${TR_TORRENT_NAME}" \
      -f "${categorize}"
  )

  if [[ ${TR_TORRENT_DIR} != "${seed_dir}" && ${root} != "${TR_TORRENT_DIR}" ]]; then
    error+=("${TR_TORRENT_NAME} -> ${root}")
    color='31'
  else
    case "${root}" in
      "${tv_dir}") color='32' ;;
      "${film_dir}") color='33' ;;
      "${av_dir}") color='34' ;;
      *) color='0' ;;
    esac
  fi
  printf "\033[${color}m%s\n%s\033[0m\n\n" "Root: ${root}" "Dest: ${dest}"

done

if ((${#error} > 0)); then
  printf '%s\n' 'Errors:' "${error[@]}"
else
  printf '%s\n' 'Passed.'
fi

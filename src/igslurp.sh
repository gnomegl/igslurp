#!/usr/bin/env bash

# @describe Instagram API client for social media intelligence
# @arg command "Command to run (profile, user-id, following, followers, posts, highlights, reels)" [string]
# @arg value "Value to search for (username, user_id, etc.)" [string]
# @option -k --key "RapidAPI key (can also use INSTAGRAM_API_KEY env var)" [string]
# @option -m --max-id "Pagination cursor for next page" [string]
# @option -c --count "Number of items to fetch" [int] @default "25"
# @option -p --page "Page number for results pagination" [int] @default "1"
# @flag   -j --json "Output raw JSON instead of formatted results"
# @flag   -q --quiet "Suppress colored output"
# @flag   -a --auto-paginate "Automatically fetch all pages of results"
# @meta require-tools curl,jq

eval "$(argc --argc-eval "$0" "$@")"

# Initialize argc variables with defaults to avoid shellcheck warnings
argc_quiet=${argc_quiet:-0}
argc_json=${argc_json:-0}
argc_auto_paginate=${argc_auto_paginate:-0}

setup_colors() {
  if [ "$argc_quiet" = 1 ] || [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    bold="" reset="" blue="" green="" yellow="" cyan="" magenta="" red=""
  else
    bold=$(tput bold) reset=$(tput sgr0) blue=$(tput setaf 4) green=$(tput setaf 2)
    yellow=$(tput setaf 3) cyan=$(tput setaf 6) magenta=$(tput setaf 5) red=$(tput setaf 1)
  fi
}
setup_colors

get_api_key() {
  if [ -n "$argc_key" ]; then
    echo "$argc_key"
  elif [ -n "$INSTAGRAM_API_KEY" ]; then
    echo "$INSTAGRAM_API_KEY"
  elif [ -f "$HOME/.config/instagram/api_key" ]; then
    cat "$HOME/.config/instagram/api_key"
  else
    echo "${red}Error:${reset} No Instagram API key found." >&2
    echo "Either:" >&2
    echo "  1. Pass it with --key" >&2
    echo "  2. Set INSTAGRAM_API_KEY environment variable" >&2
    echo "  3. Save it to ~/.config/instagram/api_key" >&2
    exit 1
  fi
}
API_KEY=$(get_api_key)
API_BASE="https://instagram-api-fast-reliable-data-scraper.p.rapidapi.com"

print_kv() {
  printf "${bold}%s:${reset} %s\n" "$1" "$2"
}

print_section() {
  printf "\n${bold}%s:${reset}\n" "$1"
}

format_number() {
  printf "%'d" "$1" 2>/dev/null || echo "$1"
}

make_request() {
  local endpoint="$1"
  local params="$2"
  local url="${API_BASE}/${endpoint}${params}"

  local response
  response=$(curl -s \
    --header "x-rapidapi-host: instagram-api-fast-reliable-data-scraper.p.rapidapi.com" \
    --header "x-rapidapi-key: ${API_KEY}" \
    "$url")

  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    error_msg=$(echo "$response" | jq -r '.error')
    printf "${red}Error:${reset} Instagram API returned: ${red}%s${reset}\n" "$error_msg" >&2
    exit 1
  fi

  echo "$response"
}

make_paginated_request() {
  local endpoint="$1"
  local params="$2"
  local data_key="$3"
  local all_results="[]"
  local next_max_id=""
  local count=0

  while :; do
    local current_params="$params"
    [ -n "$next_max_id" ] && current_params="${current_params}&next_max_id=${next_max_id}"

    local response
    response=$(make_request "$endpoint" "$current_params")

    local page_data
    page_data=$(echo "$response" | jq ".$data_key // []")
    all_results=$(echo "$all_results" | jq --argjson new "$page_data" '. + $new')

    next_max_id=$(echo "$response" | jq -r '.next_max_id // .max_id // empty')

    count=$((count + 1))
    if [ -z "$next_max_id" ] || [ $count -ge 50 ]; then
      break
    fi

    # Small delay to be respectful to the API
    sleep 0.5
  done

  # Return combined results in the same format as single request
  echo "{\"$data_key\": $all_results}"
}

resolve_user_id() {
  local input="$1"

  # If input is numeric, it's already a user_id
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    echo "$input"
    return 0
  fi

  # Otherwise, treat as username and resolve to user_id
  printf "${cyan}Resolving username '${yellow}%s${cyan}' to user ID...${reset}\n" "$input" >&2

  local response
  response=$(make_request "user_id_by_username" "?username=${input}")
  local user_id
  user_id=$(echo "$response" | jq -r '.UserID')

  if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
    printf "${red}Error:${reset} Could not resolve username '${yellow}%s${red}' to user ID\n" "$input" >&2
    exit 1
  fi

  printf "${green}Found user ID: ${magenta}%s${reset}\n" "$user_id" >&2
  echo "$user_id"
}

show_help() {
  echo "${bold}Instagram API Client${reset}"
  echo ""
  echo "${bold}Commands:${reset}"
  echo "  ${cyan}profile${reset}       Get profile information by username or user_id"
  echo "  ${cyan}user-id${reset}       Get user ID by username"
  echo "  ${cyan}following${reset}     Get list of users someone is following (accepts username or user_id)"
  echo "  ${cyan}followers${reset}     Get list of followers (accepts username or user_id)"
  echo "  ${cyan}posts${reset}         Get user's posts"
  echo "  ${cyan}highlights${reset}    Get user's story highlights"
  echo "  ${cyan}reels${reset}         Get user's reels (accepts username or user_id)"
  echo ""
  echo "${bold}Examples:${reset}"
  echo "  ${green}$(basename "$0") profile randomuser123${reset}"
  echo "  ${green}$(basename "$0") user-id randomuser123${reset}"
  echo "  ${green}$(basename "$0") following randomuser123${reset}"
  echo "  ${green}$(basename "$0") followers randomuser123${reset}"
  echo "  ${green}$(basename "$0") following 1234567890 --max-id 25${reset}"
  echo "  ${green}$(basename "$0") profile --value randomuser123 --json${reset}"
  echo "  ${green}$(basename "$0") reels randomuser123${reset}"
  echo ""
  echo "${bold}Options:${reset}"
  echo "  ${yellow}-k, --key${reset}       RapidAPI key"
  echo "  ${yellow}-m, --max-id${reset}    Pagination cursor"
  echo "  ${yellow}-c, --count${reset}     Number of items to fetch"
  echo "  ${yellow}-j, --json${reset}      Output raw JSON"
  echo "  ${yellow}-q, --quiet${reset}     Suppress colored output"
  echo "  ${yellow}-a, --auto-paginate${reset} Automatically fetch all pages"
}

format_profile() {
  local response="$1"
  local username
  username=$(echo "$response" | jq -r '.username')
  local full_name
  full_name=$(echo "$response" | jq -r '.full_name // "N/A"')
  local is_private
  is_private=$(echo "$response" | jq -r '.is_private')
  local is_verified
  is_verified=$(echo "$response" | jq -r '.is_verified')
  local is_business
  is_business=$(echo "$response" | jq -r '.is_business // false')
  local follower_count
  follower_count=$(echo "$response" | jq -r '.follower_count // 0')
  local following_count
  following_count=$(echo "$response" | jq -r '.following_count // 0')
  local media_count
  media_count=$(echo "$response" | jq -r '.media_count // 0')
  local biography
  biography=$(echo "$response" | jq -r '.biography // "N/A"')
  local external_url
  external_url=$(echo "$response" | jq -r '.external_url // "N/A"')
  local public_email
  public_email=$(echo "$response" | jq -r '.public_email // "N/A"')
  local category
  category=$(echo "$response" | jq -r '.category // "N/A"')
  local user_id
  user_id=$(echo "$response" | jq -r '.pk')

  printf "${bold}Profile:${reset} ${green}@%s${reset}" "$username"
  [ "$is_verified" = "true" ] && printf " %s✓%s" "${blue}" "${reset}"
  [ "$is_private" = "true" ] && printf " %s🔒%s" "${yellow}" "${reset}"
  [ "$is_business" = "true" ] && printf " %s🏢%s" "${cyan}" "${reset}"
  printf "\n"

  print_kv "Name" "${blue}${full_name}${reset}"
  print_kv "User ID" "${magenta}${user_id}${reset}"

  if [ "$biography" != "N/A" ] && [ "$biography" != "null" ]; then
    # Handle entities in biography
    local clean_bio
    clean_bio=${biography//\\n/$'\n'}
    print_kv "Bio" "$clean_bio"
  fi

  [ "$category" != "N/A" ] && print_kv "Category" "${cyan}${category}${reset}"
  [ "$public_email" != "N/A" ] && print_kv "Email" "${blue}${public_email}${reset}"
  [ "$external_url" != "N/A" ] && print_kv "Website" "${blue}${external_url}${reset}"

  print_section "Stats"
  printf "  ${cyan}Posts:${reset} ${green}%s${reset}\n" "$(format_number "$media_count")"
  printf "  ${cyan}Followers:${reset} ${green}%s${reset}\n" "$(format_number "$follower_count")"
   printf "  ${cyan}Following:${reset} ${green}%s${reset}\n" "$(format_number "$following_count")"

   local profile_pic_url
   profile_pic_url=$(echo "$response" | jq -r '.profile_pic_url // empty')
  if [ -n "$profile_pic_url" ]; then
    print_kv "Profile Picture" "${blue}${profile_pic_url}${reset}"
  fi
}

format_user_id() {
  local response="$1"
  local user_id
  user_id=$(echo "$response" | jq -r '.UserID')
  local username
  username=$(echo "$response" | jq -r '.UserName')

  printf "${bold}User:${reset} ${green}@%s${reset}\n" "$username"
  printf "${bold}ID:${reset} ${magenta}%s${reset}\n" "$user_id"
}

format_user_list() {
  local response="$1"
  local list_type="$2"
  local count
  count=$(echo "$response" | jq -r '.users | length')
  local next_max_id
  next_max_id=$(echo "$response" | jq -r '.next_max_id // "N/A"')

  printf "${bold}%s:${reset} ${green}%s${reset} users" "$list_type" "$count"
  [ "$next_max_id" != "N/A" ] && printf " (next page: ${yellow}%s${reset})" "$next_max_id"
  printf "\n\n"

  echo "$response" | jq -r '.users[] | "\(.username)|\(.full_name // "N/A")|\(.is_private)|\(.is_verified)|\(.follower_count // 0)|\(.pk)"' |
    while IFS="|" read -r username full_name is_private is_verified follower_count user_id; do
      printf "${bold}@%s${reset}" "$username"
      [ "$is_verified" = "true" ] && printf " %s✓%s" "${blue}" "${reset}"
      [ "$is_private" = "true" ] && printf " %s🔒%s" "${yellow}" "${reset}"

      if [ "$full_name" != "N/A" ]; then
        printf " - ${cyan}%s${reset}" "$full_name"
      fi

      if [ "$follower_count" != "0" ]; then
        printf " (${green}%s${reset} followers)" "$(format_number "$follower_count")"
      fi

      printf "\n  ${magenta}ID:${reset} %s\n\n" "$user_id"
    done
}

format_reels() {
  local response="$1"
  local count
  count=$(echo "$response" | jq -r '.data.items | length')
  local next_max_id
  next_max_id=$(echo "$response" | jq -r '.paging_info.max_id // "N/A"')

  printf "${bold}Reels:${reset} ${green}%s${reset} items" "$count"
  [ "$next_max_id" != "N/A" ] && printf " (next page: ${yellow}%s${reset})" "$next_max_id"
  printf "\n\n"

  echo "$response" | jq -r '.data.items[] | "\(.media.pk)|\(.media.code)|\(.media.media_type)|\(.media.taken_at)|\(.media.caption.text // "N/A")|\(.media.user.username)|\(.media.user.full_name // "N/A")|\(.media.user.is_verified)|\(.media.like_count // 0)|\(.media.comment_count // 0)|\(.media.play_count // 0)|\(.media.video_duration // 0)"' |
    while IFS="|" read -r media_id code media_type taken_at caption_text username full_name is_verified like_count comment_count play_count duration; do
      if [[ "$taken_at" =~ ^[0-9]+$ ]]; then
        formatted_date=$(date -d "@$taken_at" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
      else
        formatted_date="N/A"
      fi

      case "$media_type" in
        1) media_type_name="Photo" ;;
        2) media_type_name="Video" ;;
        8) media_type_name="Album" ;;
        *) media_type_name="Unknown" ;;
      esac

      if [[ "$duration" =~ ^[0-9]*\.?[0-9]+$ ]] && (( $(echo "$duration > 0" | bc -l 2>/dev/null || echo "0") )); then
        duration_str=$(printf "%.1fs" "$duration")
      else
        duration_str="N/A"
      fi

      printf "${bold}%s${reset} ${cyan}(%s)${reset}" "$code" "$media_type_name"
      [ "$is_verified" = "true" ] && printf " %s✓%s" "${blue}" "${reset}"
      printf "\n"

      printf "  ${magenta}ID:${reset} %s\n" "$media_id"
      printf "  ${cyan}User:${reset} ${green}@%s${reset}" "$username"
      [ "$full_name" != "N/A" ] && printf " (${cyan}%s${reset})" "$full_name"
      printf "\n"
      printf "  ${cyan}Date:${reset} %s\n" "$formatted_date"

      if [ "$duration_str" != "N/A" ]; then
         printf "  ${cyan}Duration:${reset} %s\n" "$duration_str"
       fi

       print_section "Stats"
      printf "  ${green}Likes:${reset} %s\n" "$(format_number "$like_count")"
      printf "  ${yellow}Comments:${reset} %s\n" "$(format_number "$comment_count")"
      printf "  ${blue}Plays:${reset} %s\n" "$(format_number "$play_count")"

      # Show caption (truncated if too long)
      if [ "$caption_text" != "N/A" ] && [ -n "$caption_text" ]; then
        print_section "Caption"
        # Truncate very long captions
        if [ ${#caption_text} -gt 300 ]; then
          printf "  %s...\n" "${caption_text:0:300}"
        else
          printf "  %s\n" "$caption_text"
        fi
      fi

      printf "\n%s─────────────────────────────────────%s\n\n" "${bold}" "${reset}"
    done
}

if [ -z "$argc_command" ]; then
  show_help
  exit 0
fi

case "$argc_command" in
profile)
  if [ -z "$argc_value" ]; then
    echo "${red}Error:${reset} Username or user_id is required." >&2
    exit 1
  fi

  # Check if value looks like a user_id (numeric) or username
  if [[ "$argc_value" =~ ^[0-9]+$ ]]; then
    params="?user_id=${argc_value}"
  else
    params="?username=${argc_value}"
  fi

  response=$(make_request "profile" "$params")
  [ "$argc_json" = 1 ] && echo "$response" | jq || format_profile "$response"
  ;;

user-id)
  if [ -z "$argc_value" ]; then
    echo "${red}Error:${reset} Username is required." >&2
    exit 1
  fi
  params="?username=${argc_value}"
  response=$(make_request "user_id_by_username" "$params")
  [ "$argc_json" = 1 ] && echo "$response" | jq || format_user_id "$response"
  ;;

 following)
  if [ -z "$argc_value" ]; then
    echo "${red}Error:${reset} Username or user ID is required." >&2
    exit 1
  fi

  # Resolve username to user_id if needed
  user_id=$(resolve_user_id "$argc_value")
  params="?user_id=${user_id}"
  [ -n "$argc_max_id" ] && params="${params}&next_max_id=${argc_max_id}"
  [ -n "$argc_count" ] && params="${params}&count=${argc_count}"

  if [ "$argc_auto_paginate" = 1 ]; then
    response=$(make_paginated_request "following" "$params" "users")
  else
    response=$(make_request "following" "$params")
  fi
  [ "$argc_json" = 1 ] && echo "$response" | jq || format_user_list "$response" "Following"
  ;;

 followers)
  if [ -z "$argc_value" ]; then
    echo "${red}Error:${reset} Username or user ID is required." >&2
    exit 1
  fi

  # Resolve username to user_id if needed
  user_id=$(resolve_user_id "$argc_value")
  params="?user_id=${user_id}"
  [ -n "$argc_max_id" ] && params="${params}&next_max_id=${argc_max_id}"
  [ -n "$argc_count" ] && params="${params}&count=${argc_count}"

  if [ "$argc_auto_paginate" = 1 ]; then
    response=$(make_paginated_request "followers" "$params")
  else
    response=$(make_request "followers" "$params")
  fi
  [ "$argc_json" = 1 ] && echo "$response" | jq || format_user_list "$response" "Followers"
  ;;

 posts)
  if [ -z "$argc_value" ]; then
    echo "${red}Error:${reset} User ID or username is required." >&2
    exit 1
  fi

  if [[ "$argc_value" =~ ^[0-9]+$ ]]; then
    params="?user_id=${argc_value}"
  else
    params="?username=${argc_value}"
  fi
  [ -n "$argc_max_id" ] && params="${params}&next_max_id=${argc_max_id}"
  [ -n "$argc_count" ] && params="${params}&count=${argc_count}"

  if [ "$argc_auto_paginate" = 1 ]; then
    response=$(make_paginated_request "feed" "$params" "items")
  else
    response=$(make_request "feed" "$params")
  fi
  [ "$argc_json" = 1 ] && echo "$response" | jq || echo "$response" | jq
  ;;

highlights)
  if [ -z "$argc_value" ]; then
    echo "${red}Error:${reset} User ID or username is required." >&2
    exit 1
  fi

  if [[ "$argc_value" =~ ^[0-9]+$ ]]; then
    params="?user_id=${argc_value}"
  else
    params="?username=${argc_value}"
  fi

  response=$(make_request "highlights" "$params")
  [ "$argc_json" = 1 ] && echo "$response" | jq || echo "$response" | jq
  ;;

   reels)
     if [ -z "$argc_value" ]; then
       echo "${red}Error:${reset} Username or user ID is required." >&2
       exit 1
     fi

     # Resolve username to user_id if needed
     user_id=$(resolve_user_id "$argc_value")
     params="?user_id=${user_id}"
     [ -n "$argc_max_id" ] && params="${params}&next_max_id=${argc_max_id}"
     [ -n "$argc_count" ] && params="${params}&count=${argc_count}"

     if [ "$argc_auto_paginate" = 1 ]; then
       response=$(make_paginated_request "reels" "$params" "data.items")
     else
       response=$(make_request "reels" "$params")
     fi
     [ "$argc_json" = 1 ] && echo "$response" | jq || format_reels "$response"
     ;;

*)
  echo "${red}Error:${reset} Unknown command: ${argc_command}" >&2
  show_help
  exit 1
  ;;
esac

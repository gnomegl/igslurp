# igslurp

[![basher install](https://www.basher.it/assets/logo/basher_install.svg)](https://www.basher.it/package/)

instagram data collection tool

## install

```bash
basher install gnomegl/igslurp
```

## usage

```bash
igslurp [command] [username/id]
```

fetch instagram profiles, posts, followers, and more.

## commands

- `profile` - get user profile
- `user-id` - convert username to id
- `following` - list following
- `followers` - list followers
- `posts` - fetch user posts
- `highlights` - get story highlights
- `reels` - fetch reels

## config

set api key:
```bash
export INSTAGRAM_API_KEY="your_key"
```

## requirements

- curl
- jq
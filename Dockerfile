ARG MIX_ENV="prod"

FROM hexpm/elixir:1.13.0-rc.0-erlang-24.1.4-alpine-3.13.6 as build

# install build dependencies
RUN apk add --no-cache build-base git python3 curl

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

COPY priv priv

# note: if your project uses a tool like https://purgecss.com/,
# which customizes asset compilation based on what it finds in
# your Elixir templates, you will need to move the asset compilation
# step down so that `lib` is available.
COPY assets assets
RUN mix assets.deploy

# compile and build the release
COPY lib lib
RUN mix compile
# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/
# uncomment COPY if rel/ exists
# COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM alpine:3.13.6 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs

ARG MIX_ENV
ENV USER="conradwt"

# WORKDIR "/home/${USER}/app"
WORKDIR /app

RUN chown nobody:nobody /app

# Creates an unprivileged user to be used exclusively to run the Phoenix app
RUN \
  addgroup \
   -g 1000 \
   -S "${USER}" \
  && adduser \
   -s /bin/sh \
   -u 1000 \
   -G "${USER}" \
   -h "/home/${USER}" \
   -D "${USER}" \
  && su "${USER}"

# Everything from this line onwards will run in the context of the unprivileged user.
USER "${USER}"

COPY --from=build --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/hello_fly ./

ENV HOME=/app
ENV MIX_ENV=prod
ENV SECRET_KEY_BASE=nokey
ENV PORT=4000

CMD ["bin/hello_fly", "start"]
ARG SRC="https://github.com/php/php-src.git"
ARG VER="php-8.1.7"
ARG APCU_SRC="https://github.com/krakjoe/apcu.git"
ARG APCU_VER="v5.1.21"
ARG OWNER="manarth"
ARG REPO="php-static"

##################
# INCLUDE LIBZIP #
##################
FROM ghcr.io/manarth/libzip-static:1.9.2 AS libzip

##################
# INCLUDE LIBICU #
##################
FROM ghcr.io/manarth/icu-static AS icu

#############
# BUILD PHP #
#############
FROM alpine:3.16 AS build-php
ARG SRC
ARG VER
ARG APCU_SRC
ARG APCU_VER

# Install basic utilities.
RUN apk add git patch

# Checkout the relevant PHP branch.
RUN git clone --depth 1 --branch ${VER} ${SRC} /opt/php-src

# Required to compile PHP from source.
RUN apk add autoconf automake bison g++ gcc libc-dev libtool make re2c

# Copy the static-build of libzip.
COPY --from=libzip /lib/libzip.a /lib/

# Extension-specific libraries.
RUN apk add bzip2-dev curl-dev icu-dev libgcrypt-dev libjpeg-turbo-dev libpq-dev libpng-dev libsodium-dev libwebp-dev  libxml2-dev libxslt-dev libzip-dev ncurses-dev oniguruma-dev readline-dev sqlite-dev tidyhtml-dev

# Static versions of the libraries for extensions.
RUN apk add bzip2-static curl-static icu-static libgcrypt-static libgpg-error-static libjpeg-turbo-static libpng-static libsodium-static libwebp-static ncurses-static readline-static sqlite-static tidyhtml-static zlib-static

# Static lib dependencies of the static libs.
RUN apk add brotli-static nghttp2-static openssl-libs-static zstd-static

WORKDIR /opt/php-src

# Add `apcu` to the extension catalogue.
RUN git clone --depth 1 --branch ${APCU_VER} ${APCU_SRC} /opt/php-src/ext/apcu

# Core patches for static linking.
COPY readline_cli.patch /tmp
RUN patch -p1 < /tmp/readline_cli.patch

# Copy icu-static from the build, so the data file is packaged.
COPY --from=icu /usr/lib/* /usr/lib

# Initialise the build environment.
RUN ./buildconf --force

# Configure the build.
RUN ./configure \
  # Set directories.
  --exec-prefix=/usr \
  --datarootdir=/usr/share \
  --prefix= \
  --sysconfdir=/etc/php \
  --with-config-file-path=/etc/php/ \
  --with-config-file-scan-dir=/etc/php/conf.d/ \
  # Use static-linking to create a self-contained binary.
  --disable-shared \
  --enable-static \
  # Select SAPI and basic configuration.
  --disable-cgi \
  --disable-phpdbg \
  --disable-short-tags \
  --enable-fpm \
  --enable-zts \
  --without-apxs2 \
  # Standard capabilities.
  --enable-bcmath \
  --enable-gd \
  --enable-intl \
  --enable-mbstring \
  --enable-pcntl \
  --enable-soap \
  --enable-sockets \
  # Standard extensions.
  --with-bz2 \
  --with-curl \
  --with-jpeg \
  --with-libxml \
  --with-openssl \
  --with-pdo-mysql \
  --with-pdo-pgsql \
  --with-readline \
  --with-sodium \
  --with-sqlite3 \
  --with-tidy \
  --with-webp \
  --with-xsl \
  --with-zip \
  --with-zlib \
  # PECL extensions.
  --enable-apcu

# Speed up repeated runs with the use of prep stages which builds the PHP objects.
RUN printf "\n\n%s\n\n%s\n\n%s\n\n\n" \
    'prepare-static-global: $(PHP_GLOBAL_OBJS)' \
    'prepare-static-binary: $(PHP_BINARY_OBJS)' \
    'prepare-static-cli: $(PHP_CLI_OBJS)' \
    | tee -a Makefile

RUN make prepare-static-global -j $(nproc)
RUN make prepare-static-binary -j $(nproc)
RUN make prepare-static-cli -j $(nproc)

# Add the static-library dependencies as a variable to the Makefile.
RUN printf "\n# %s\n%s\n\n" \
    'Added by static-builder.' \
    'STATIC_EXTRA_LIBS="-lstdc++ -l:libnghttp2.a -l:libgcrypt.a -l:libgpg-error.a -l:libncurses.a -l:libpq.a  -l:libpgport.a -l:libpgcommon.a -l:libreadline.a -l:libssl.a -l:libcrypto.a -l:libbrotlidec.a -l:libbrotlicommon.a -l:liblzma.a"' \
    | tee -a Makefile

# Add a new Makefile target to statically build the CLI SAPI.
RUN printf "%s\n%s\n\t%s\n\n" \
    'BUILD_STATIC_CLI = $(LIBTOOL) --mode=link $(CC) -export-dynamic -all-static $(CFLAGS_CLEAN) $(EXTRA_CFLAGS) $(EXTRA_LDFLAGS_PROGRAM) $(LDFLAGS) $(PHP_RPATHS) $(PHP_GLOBAL_OBJS:.lo=.o) $(PHP_BINARY_OBJS:.lo=.o) $(PHP_CLI_OBJS:.lo=.o) $(EXTRA_LIBS) $(ZEND_EXTRA_LIBS) $(STATIC_EXTRA_LIBS) -o $(SAPI_CLI_PATH)' \
    'cli-static: $(PHP_GLOBAL_OBJS) $(PHP_BINARY_OBJS) $(PHP_CLI_OBJS)' \
    '$(BUILD_STATIC_CLI)' \
    | tee -a Makefile

# Add a new Makefile target to statically build the FPM SAPI.
RUN printf "%s\n%s\n\t%s\n\n" \
    'BUILD_STATIC_FPM = $(LIBTOOL) --mode=link $(CC) -export-dynamic -all-static $(CFLAGS_CLEAN) $(EXTRA_CFLAGS) $(EXTRA_LDFLAGS_PROGRAM) $(LDFLAGS) $(PHP_RPATHS) $(PHP_GLOBAL_OBJS:.lo=.o) $(PHP_BINARY_OBJS:.lo=.o) $(PHP_FASTCGI_OBJS:.lo=.o) $(PHP_FPM_OBJS:.lo=.o) $(EXTRA_LIBS) $(FPM_EXTRA_LIBS) $(ZEND_EXTRA_LIBS) $(STATIC_EXTRA_LIBS) -o $(SAPI_FPM_PATH)' \
    'fpm-static: $(PHP_GLOBAL_OBJS) $(PHP_BINARY_OBJS) $(PHP_FASTCGI_OBJS) $(PHP_FPM_OBJS)' \
    '$(BUILD_STATIC_FPM)' \
    | tee -a Makefile

# # Compile CLI.
RUN make cli-static -j $(nproc)
RUN strip --strip-all /opt/php-src/sapi/cli/php

# Unpatch readline to compile for PHP-FPM
RUN patch -p1 -R < /tmp/readline_cli.patch
RUN make ext/readline/readline_cli.lo

# Compile PHP-FPM.
RUN make fpm-static -j $(nproc)
RUN strip --strip-all /opt/php-src/sapi/fpm/php-fpm

ARG TARGETARCH

# UPX release links.
# https://github.com/upx/upx/releases/download/v3.96/upx-3.96-amd64_linux.tar.xz
# https://github.com/upx/upx/releases/download/v3.96/upx-3.96-arm64_linux.tar.xz
ADD https://github.com/upx/upx/releases/download/v3.96/upx-3.96-${TARGETARCH}_linux.tar.xz /tmp/upx.tar.xz
RUN cd /tmp && tar -xJf /tmp/upx.tar.xz
RUN mv /tmp/upx-3.96-${TARGETARCH}_linux/upx /usr/bin/upx

# Don't run UPX for arm64 until the issues have been identified and resolved.
RUN (test `uname -m` != "aarch64" && upx -9 /opt/php-src/sapi/cli/php) || true
RUN (test `uname -m` != "aarch64" && upx -9 /opt/php-src/sapi/fpm/php-fpm) || true

# Package to a minimal release.
FROM scratch as dist
ARG SRC
ARG VER
ARG OWNER
ARG REPO

LABEL php.source=${SRC}
LABEL php.version=${VER}
LABEL org.opencontainers.image.source https://github.com/${OWNER}/${REPO}

STOPSIGNAL SIGTERM

# Copy assets, including sample configurations.
COPY --from=build-php /opt/php-src/sapi/cli/php           /usr/bin/php
COPY --from=build-php /opt/php-src/sapi/fpm/php-fpm       /usr/sbin/php-fpm
COPY --from=build-php /opt/php-src/php.ini-production     /etc/php/php.ini
COPY --from=build-php /opt/php-src/sapi/fpm/php-fpm.conf  /etc/php/php-fpm.conf
COPY --from=build-php /opt/php-src/sapi/fpm/www.conf      /etc/php/php-fpm.d/www.conf.EXAMPLE

# Provision a default set of SSL certificates.
COPY --from=alpine:latest /etc/ssl/certs /etc/ssl/certs

FROM nginx:1.19.5-alpine AS config

FROM alpine:3.12

LABEL maintainer="Domenico Shura <shura1991@gmail.com>"

ENV NGINX_VERSION 1.19.5

COPY --from=config /docker-entrypoint.d/* /docker-entrypoint.d/
COPY --from=config /docker-entrypoint.sh /docker-entrypoint.sh

RUN set -eux; \
    \
    test "$(getent group nginx 2>/dev/null | cut -d: -f3)" = 101 || \
    addgroup -g 101 -S nginx; \
    \
    test "$(id -u nginx 2>/dev/null)" = 101 || \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx; \
    \
    apk add --no-cache \
    pcre \
    zlib \
    openssl \
    curl \
    ca-certificates \
    tzdata \
    libxslt \
    gd \
    geoip \
    perl \
    ; \
    \
    apk add --no-cache --virtual .build \
    git \
    mercurial \
    patch \
    pcre-dev \
    zlib-dev \
    gcc \
    g++ \
    libc-dev \
    linux-headers \
    openssl-dev \
    make \
    cmake \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    perl-dev \
    ; \
    \
    prevPath="$PATH"; \
    curl https://sh.rustup.rs -sSf | sh -s -- -y -q; \
    source ~/.cargo/env; \
    \
    tmpDir="$(mktemp -d)"; \
    cd "$tmpDir"; \
    curl -O https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz; \
    tar xzf nginx-${NGINX_VERSION}.tar.gz; \
    rm -f nginx-${NGINX_VERSION}.tar.gz; \
    git clone --recursive https://github.com/cloudflare/quiche; \
    git clone --recursive https://github.com/google/ngx_brotli.git; \
    hg clone http://hg.nginx.org/njs; \
    \
    cd nginx-$NGINX_VERSION; \
    patch -p01 < ../quiche/extras/nginx/nginx-1.16.patch; \
    \
    ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --with-perl_modules_path=/usr/lib/perl5/vendor_perl \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-cc-opt='-Os -fomit-frame-pointer' \
    --with-ld-opt=-Wl,--as-needed \
    --with-http_geoip_module=dynamic \
    --with-http_xslt_module=dynamic \
    --with-http_image_filter_module=dynamic \
    --add-dynamic-module="$tmpDir"/njs/nginx \
    --add-module="$tmpDir"/ngx_brotli \
    --with-http_v3_module \
    --with-openssl="$tmpDir"/quiche/deps/boringssl \
    --with-quiche="$tmpDir"/quiche; \
    make -j "$(nproc)"; \
    make install; \
    \
    cd; rm -rf "$tmpDir" ~/.rustup ~/.cargo; \
    apk del --purge .build; \
    rm -rf /var/cache/apk/*; \
    export PATH="$prevPath"; \
    unset tmpDir; \
    unset prevPath; \
    \
    apk add --no-cache --virtual .gettext gettext; \
    mv /usr/bin/envsubst /tmp/; \
    runDeps="$( \
    scanelf --needed --nobanner /tmp/envsubst \
    | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
    | sort -u \
    | xargs -r apk info --installed \
    | sort -u \
    )"; \
    apk add --no-cache $runDeps; \
    apk del .gettext; \
    mv /tmp/envsubst /usr/local/bin/; \
    \
    mkdir -p /var/log/nginx; \
    rm -f /var/log/nginx/access.log /var/log/nginx/error.log; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    mkdir -m 0755 -p /usr/share/nginx; \
    rm -rf /usr/share/nginx/html; \
    mv /etc/nginx/html /usr/share/nginx/html; \
    chown -R nginx:nginx /var/log/nginx; \
    rm -f /etc/nginx/*.default /etc/nginx/nginx.conf; \
    ln -sf /usr/lib/nginx/modules /etc/nginx/modules; \
    mkdir -p /var/cache/nginx/client_temp; \
    mkdir -p /var/cache/nginx/proxy_temp; \
    mkdir -p /var/cache/nginx/fastcgi_temp; \
    mkdir -p /var/cache/nginx/uwsgi_temp; \
    mkdir -p /var/cache/nginx/scgi_temp; \
    chown -R nginx:nginx /var/cache/nginx

COPY conf/ /etc/nginx/

ENTRYPOINT [ "/docker-entrypoint.sh" ]

EXPOSE 80/tcp
EXPOSE 443/tcp

STOPSIGNAL SIGTERM

CMD [ "nginx", "-g", "daemon off;" ]
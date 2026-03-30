FROM hugomods/hugo:reg-base-0.140.2 AS builder
WORKDIR /site
COPY . .
RUN hugo --minify

FROM nginx:alpine
RUN apk add --no-cache curl && \
    mkdir -p /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chown -R nginx:nginx /var/cache/nginx /run /var/log/nginx /etc/nginx/conf.d
COPY --from=builder /site/public /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 5100
USER nginx

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5100/ || exit 1

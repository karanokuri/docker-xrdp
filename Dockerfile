FROM alpine:3.12 as builder

ARG PULSEAUDIO_MODULE_XRDP_VERSION="v0.4"

RUN apk add \
      alpine-sdk \
      pulseaudio-dev \
      sudo

RUN addgroup builder \
 && adduser -G builder -s /bin/sh -D builder \
 && echo "builder:builder"| /usr/sbin/chpasswd \
 && echo "builder    ALL=(ALL) ALL" >> /etc/sudoers \
 && sudo addgroup builder abuild

RUN chmod g+w /var/cache/distfiles

USER builder

RUN mkdir /tmp/aports \
 && cd /tmp/aports \
 && git init \
 && git config core.sparsecheckout true \
 && git remote add origin https://github.com/alpinelinux/aports.git \
 && echo community/xrdp       >> .git/info/sparse-checkout \
 && echo community/pulseaudio >> .git/info/sparse-checkout \
 && git pull origin 3.12-stable

RUN abuild-keygen -a -n

RUN cd /tmp/aports/community/xrdp \
 && abuild fetch \
 && abuild unpack \
 && abuild deps \
 && abuild prepare \
 && abuild build \
 && abuild rootpkg

RUN cd /tmp/aports/community/pulseaudio \
 && abuild fetch \
 && abuild unpack \
 && abuild deps \
 && abuild prepare \
 && abuild build \
 && abuild rootpkg

RUN cd /tmp/aports/community/pulseaudio/src/pulseaudio-13.0 \
 && cp ./output/config.h . \
 && mkdir /tmp/pulseaudio-module-xrdp \
 && wget https://github.com/neutrinolabs/pulseaudio-module-xrdp/archive/${PULSEAUDIO_MODULE_XRDP_VERSION}.tar.gz -O - \
    | tar xzC /tmp/pulseaudio-module-xrdp --strip=1 \
 && cd /tmp/pulseaudio-module-xrdp \
 && ./bootstrap \
 && ./configure PULSE_DIR=/tmp/aports/community/pulseaudio/src/pulseaudio-13.0 \
 && make \
 && echo builder | sudo -S make install



FROM alpine:3.12

RUN apk add --no-cache \
      openbox \
      pulseaudio \
      supervisor \
      ttf-cantarell \
      xorg-server \
      xrdp \
 && apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
      xorgxrdp \
 && rm -rf /tmp/* /var/cache/apk/*

COPY --from=builder /usr/lib/pulse-13.0/modules /usr/lib/pulse-13.0/modules
COPY --from=builder /tmp/pulseaudio-module-xrdp/build-aux/install-sh /bin
RUN install-sh -c -d '/usr/lib/pulse-13.0/modules' \
 && ldconfig -n /usr/lib/pulse-13.0/modules

ADD etc /etc

RUN addgroup alpine \
 && adduser -G alpine -s /bin/sh -D alpine \
 && echo "alpine:alpine" | /usr/sbin/chpasswd \
 && echo "alpine    ALL=(ALL) ALL" >> /etc/sudoers

EXPOSE 3389
CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]

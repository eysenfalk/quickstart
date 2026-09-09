FROM debian:12

ENV container=docker DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl dbus git openssh-client openssh-server sudo systemd systemd-sysv xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl enable ssh.service \
    && mkdir -p /etc/systemd/journald.conf.d \
    && printf 'ReadKMsg=no\n' >/etc/systemd/journald.conf.d/container.conf

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

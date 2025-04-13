# syntax=docker/dockerfile:1.5
FROM phusion/baseimage:jammy-1.0.1

ARG NOBODY_UID=99
ARG NOBODY_GID=100
ARG FFMPEG_VER=7.1.1

# Set correct environment variables
ENV HOME /root
ENV DEBIAN_FRONTEND noninteractive
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Use baseimage-docker's init system
CMD ["/sbin/my_init"]

# Move Files
COPY root/ /

RUN <<-eot
    #!/usr/bin/env bash
    usermod -u ${NOBODY_UID} nobody
    usermod -g ${NOBODY_GID} nobody
    usermod -d /home nobody
    chown -R nobody:users /home

    chmod +x /etc/my_init.d/*.sh
    chmod -R 777 /tmp
  
    apt-get update
    apt-get install -y --allow-unauthenticated --no-install-recommends \
        abcde \
	adduser \
        ccextractor \
        curl \
        eject \
        eyed3 \
        ffmpeg \
        flac \
        gddrescue \
        id3 \
        id3v2 \
        lame \
	libcurl4 \
        mkcue \
        python3 \
        python3-pip \
        sdparm \
        speex \
        vorbis-tools \
        vorbisgain

    pip3 install docopt flask waitress
    apt-get -y autoremove
    apt-get clean

    rm -rf /etc/service/sshd /etc/my_init.d/00_regen_ssh_host_keys.sh
eot

# invalidate build cache on forum post change
ADD "https://forum.makemkv.com/forum/viewtopic.php?f=3&t=224" latest_post

# Setup taken from https://github.com/tianon/dockerfiles/blob/master/makemkv/Dockerfile
# The Expat/MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the 
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software. 
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL 
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
# DEALINGS IN THE SOFTWARE.
RUN <<-eot
    #!/usr/bin/env bash
    set -ex

    mkdir -p /usr/share/man/man1
    apt-get install -y --no-install-recommends openjdk-11-jre-headless

    savedAptMark=$(apt-mark showmanual)
    # libavcodec-dev
    apt-get install -y --no-install-recommends ca-certificates g++ gcc gnupg dirmngr libexpat-dev libssl-dev make pkg-config qtbase5-dev wget zlib1g-dev yasm libfdk-aac-dev
    apt-get clean

    (
    wget -O ffmpeg.tar.gz https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.gz
    tar -xzf ffmpeg.tar.gz  
    cd ffmpeg-${FFMPEG_VER}
    ./configure --prefix=/tmp/ffmpeg --enable-static --disable-shared --enable-pic --enable-libfdk-aac
    make install 
    )

    PKG_CONFIG_PATH=/tmp/ffmpeg/lib/pkgconfig
    export PKG_CONFIG_PATH

    MAKEMKV_VERSION=$(curl --silent 'https://forum.makemkv.com/forum/viewtopic.php?f=3&t=224' \
	| awk -vRS="</a>" '{ gsub(/.*<a +href=\042/,""); gsub(/\042.*/,""); print; }' \
	| grep -e "^https://www.makemkv.com/download/makemkv-.*tar.gz$" \
	| cut -d- -f3- | cut -d. -f1-3 | uniq | sort | tail -n1)
    
    wget -O 'sha256sums.txt.sig' "https://www.makemkv.com/download/makemkv-sha-${MAKEMKV_VERSION}.txt"
    export GNUPGHOME=$(mktemp -d)
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 2ECF23305F1FC0B32001673394E3083A18042697
    gpg --batch --decrypt --output sha256sums.txt sha256sums.txt.sig
    gpgconf --kill all
    rm -rf "$GNUPGHOME" sha256sums.txt.sig
    
    export PREFIX='/usr/local'
    for ball in makemkv-oss makemkv-bin; do
        wget -O "$ball.tgz" "https://www.makemkv.com/download/${ball}-${MAKEMKV_VERSION}.tar.gz"
        sha256=$(grep "  $ball-${MAKEMKV_VERSION}[.]tar[.]gz\$" sha256sums.txt)
        sha256=${sha256%% *}
        [ -n "$sha256" ]
        echo "$sha256 *$ball.tgz" | sha256sum -c -
        mkdir -p "$ball"
        tar -xvf "$ball.tgz" -C "$ball" --strip-components=1
        rm "$ball.tgz"
        cd "$ball"
        if [ -f configure ]; then
            ./configure --prefix="$PREFIX" --disable-gui --disable-qt5
        else
            mkdir -p tmp
            touch tmp/eula_accepted
        fi
        make -j "$(nproc)" PREFIX="$PREFIX"
        make install PREFIX="$PREFIX"
        cd ..
        rm -r "$ball"
    done
    
    apt-mark auto '.*' > /dev/null
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark
    find /usr/local -type f -executable -exec ldd '{}' ';' \
        | awk '/=>/ { print $(NF-1) }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual \
    
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
    
    # Clean up temp files
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/*
eot

ENV PATH="$PATH:/usr/local/bin:/usr/local/sbin"

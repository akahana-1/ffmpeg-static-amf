FROM debian:12
ENV DEBIAN_FRONTEND noninteractive
ARG FFMPEG_VERSION="7.0.2"
ARG PROCS=4

RUN set -x \
	&& apt-get update -qq \
	&& apt-get install -y --no-install-recommends \
	build-essential \
	autoconf \
	automake \
	libtool \
	git \
	cmake \
	pkg-config \
	libfreetype6-dev \
	libssl-dev \
	libtls-dev \
	libcrypt-dev \
	libgl1-mesa-dev \
	libdrm-dev \
	meson \
	ninja-build \
	yasm \
	zlib1g-dev \
	libunistring-dev \
	libvorbis-dev \
	libx265-dev \
	texinfo \
	curl \
	wget \
	ca-certificates \
	&& mkdir -p /tmp/ffmpeg_sources /tmp/ffmpeg_build /root/.bin

WORKDIR /tmp/ffmpeg_sources
ENV PATH "/root/.bin:$PATH"

# get NASM
RUN curl -o nasm.tar.xz -L https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz \
	&& mkdir nasm \
	&& tar --strip-components=1 -xf nasm.tar.xz -C nasm \
	&& cd nasm \
	&& ./autogen.sh \
	&& ./configure --prefix="/tmp/ffmpeg_build" --bindir="/root/.bin" \
	&& make -j ${PROCS} \
	&& make install

# get mp3 library (lame)
RUN curl -o lame.tar.gz -L https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download \
	&& mkdir lame \
	&& tar --strip-components=1 -xf lame.tar.gz -C lame \
	&& cd lame \
	&& ./configure --prefix="/tmp/ffmpeg_build" --enable-nasm --disable-shared \
	&& make -j ${PROCS} \
	&& make install

# get aac library
RUN git clone --depth 1 -b v2.0.3 https://github.com/mstorsjo/fdk-aac \
	&& cd fdk-aac \
	&& autoreconf -fiv \
	&& ./configure --prefix="/tmp/ffmpeg_build" --disable-shared \
	&& make -j ${PROCS} \
	&& make install

# get opus library
RUN git clone --depth 1 -b v1.5.2 https://github.com/xiph/opus.git \
	&& cd opus \
	&& ./autogen.sh \
	&& ./configure --prefix="/tmp/ffmpeg_build" --disable-shared \
	&& make -j ${PROCS} \
	&& make install

# get vorbis library
RUN git clone --depth 1 -b v1.3.7 https://github.com/xiph/vorbis \
	&& cd vorbis \
	&& ./autogen.sh \
	&& ./configure --prefix="/tmp/ffmpeg_build" --disable-shared \
	&& make -j ${PROCS} \
	&& make install

# get x264 library
RUN git -C x264 pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/x264.git -b stable \
	&& cd x264 \
	&& PKG_CONFIG_PATH="/tmp/ffmpeg_build" \
	./configure --prefix="/tmp/ffmpeg_build" --bindir="/root/.bin" --enable-static --enable-pic \
	&& make -j ${PROCS} \
	&& make install

# get x265 library
RUN git clone --depth 1 -b 3.6 https://bitbucket.org/multicoreware/x265_git.git x265 \
	&& cd x265/build/linux \
	&& cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/tmp/ffmpeg_build" \
	-DENABLE_SHARED:BOOL=OFF -DSTATIC_LINK_CRT:BOOL=ON \
	-DENABLE_CLI:BOOL=OFF -DBUILD_SHARED_LIBS:BOOL=OFF \
	../../source \
	&& sed -i 's/-lgcc_s/-lgcc_eh/g' x265.pc \
	&& make -j ${PROCS} \
	&& make install

# get av1 decode library (dav1d)
RUN git clone --depth 1 -b 1.4.2 https://code.videolan.org/videolan/dav1d \
	&& mkdir dav1d/build \
	&& cd dav1d/build \
	&& meson setup -Denable_tools=false \
	-Denable_tests=false \
	--default-library=static \
	--prefix "/tmp/ffmpeg_build" \
	--libdir "/tmp/ffmpeg_build/lib" \
	.. \
	&& ninja -j ${PROCS} \
	&& ninja install

# get av1 library (svt-av1)
RUN git clone --depth 1 -b v2.1.2 https://gitlab.com/AOMediaCodec/SVT-AV1 \
	&& mkdir SVT-AV1/build \
	&& cd SVT-AV1/build \
	&& cmake -G "Unix Makefiles" \
	-DCMAKE_INSTALL_PREFIX="/tmp/ffmpeg_build" \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_DEC=OFF \
	-DBUILD_SHARED_LIBS=OFF \
	.. \
	&& make -j ${PROCS} \
	&& make install

# get av1 library (aom-av1)

# get amf
RUN git clone --depth 1 -b 1.4.21 https://github.com/GPUOpen-LibrariesAndSDKs/AMF \
	&& cp -r AMF/amf/public/include /tmp/ffmpeg_build/include/AMF

# image library

# get png library
RUN curl -L -o libpng.tar.xz http://prdownloads.sourceforge.net/libpng/libpng-1.6.38.tar.xz \
	&& mkdir libpng \
	&& tar --strip-components=1 -xf libpng.tar.xz -C libpng \
	&& cd libpng \
	&& ./configure --prefix="/tmp/ffmpeg_build" --disable-shared --enable-hardware-optimizations \
	--disable-dependency-tracking --enable-static \
	&& make -j ${PROCS} \
	&& make install

# get hardware accelaration
RUN git clone --depth 1 -b v2.16-branch https://github.com/intel/libva.git libva \
	&& cd libva \
	&& ./autogen.sh \
	&& ./configure --prefix="/tmp/ffmpeg_build" --disable-x11 --disable-wayland \
	--enable-static --disable-shared --disable-docs \
	&& make -j ${PROCS} \
	&& make install

# get ffmpeg source
RUN set -x && git clone --depth 1 -b n${FFMPEG_VERSION} https://github.com/FFmpeg/FFmpeg ffmpeg \
	&& cd ffmpeg \
	&& PKG_CONFIG_PATH="/tmp/ffmpeg_build/lib/pkgconfig" \
	./configure \
	--prefix="/tmp/ffmpeg_build" \
	--pkg-config-flags="--static" \
	--extra-cflags="-I/tmp/ffmpeg_build/include" \
	--extra-ldflags="-L/tmp/ffmpeg_build/lib" \
	--extra-libs="-lpthread -lm -ldl" \
	--extra-ldexeflags="-static" \
	--bindir="/root/.bin" \
	--enable-gpl \
	--enable-vaapi \
	--enable-libfdk-aac \
	--enable-libmp3lame \
	--enable-libopus \
	--enable-libdav1d \
	--enable-libsvtav1 \
	--enable-libvorbis \
	--enable-libx264 \
	--enable-libx265 \
	--enable-libtls \
	--enable-nonfree \
	--enable-small \
	--enable-static \
	--disable-shared \
	--disable-ffplay \
	--disable-doc \
	--disable-debug \
	&& make -j ${PROCS} \
	&& make install \
	&& hash -r

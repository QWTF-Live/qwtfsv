FROM ubuntu:22.04
WORKDIR /qwtfsv
EXPOSE 27500/udp
ARG FTE_CONFIG=qwtflive
RUN apt-get update \
 && apt-get install -y \
    curl \
    gcc \
    libgnutls28-dev \
    libpng-dev \
    make \
    mesa-common-dev \
    subversion \
    zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
COPY . /qwtfsv/
RUN cd /qwtfsv/fortress/dats/ \
 && curl \
    --location \
    --remote-name-all \
    https://qwtflive-dats.s3.amazonaws.com/staging/{qwprogs,csprogs,menu}.dat \
 && cd /qwtfsv/
ENTRYPOINT ["/qwtfsv/fteqw-sv"]
CMD ["-ip", "localhost", \
     "+set", "hostname", "QwtfLive", \
     "+exec", "fo_pubmode.cfg", \
     "+map", "2fort5r"]

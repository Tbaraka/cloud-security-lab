FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install basic vulnerable services + tools
RUN apt-get update && apt-get install -y \
    openssh-server \
    vsftpd \
    apache2 \
    net-tools \
    iputils-ping \
    curl \
    wget \
    sudo \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Create student user
RUN useradd -m -s /bin/bash student && \
    echo "student:student" | chpasswd && \
    adduser student sudo

# Setup SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Expose common vulnerable ports
EXPOSE 22 21 80

# Start SSH
CMD ["/usr/sbin/sshd", "-D"]
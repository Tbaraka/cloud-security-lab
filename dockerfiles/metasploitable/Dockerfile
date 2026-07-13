FROM ubuntu@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apache2 \
        openssh-server \
        vsftpd \
        net-tools \
        iputils-ping \
        curl \
        wget \
        vim \
        nano && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create SSH runtime directory
RUN mkdir -p /var/run/sshd

# Create a deliberately weak lab user
# NOTE: This is intentional for cybersecurity training.
RUN useradd -m -s /bin/bash msfadmin && \
    echo "msfadmin:msfadmin" | chpasswd

# Create a workspace for demonstrations
RUN mkdir -p /home/msfadmin/lab && \
    chown -R msfadmin:msfadmin /home/msfadmin/lab

# Copy startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Provide a simple working vsftpd config for the lab container
RUN printf '%s\n' \
    'listen=YES' \
    'listen_ipv6=NO' \
    'anonymous_enable=NO' \
    'local_enable=YES' \
    'write_enable=YES' \
    'chroot_local_user=YES' \
    'allow_writeable_chroot=YES' \
    'secure_chroot_dir=/var/run/vsftpd/empty' \
    'pam_service_name=vsftpd' \
    'pasv_enable=YES' \
    'pasv_min_port=30000' \
    'pasv_max_port=31000' \
    > /etc/vsftpd.conf

# Expose vulnerable services
EXPOSE 21 22 80

# Start all services
ENTRYPOINT ["/entrypoint.sh"]

FROM ubuntu:26.04

WORKDIR /workspace

ENV LANG=ja_JP.UTF-8 \
    LANGUAGE=ja_JP:ja \
    LC_ALL=ja_JP.UTF-8 \
  TZ=Asia/Tokyo

RUN <<-EOF
apt update
apt install -y --no-install-recommends \
  bash \
  bash-completion \
  ca-certificates \
  tzdata \
  git \
  git-lfs \
  vim \
  curl \
  jq \
  less \
  file \
  patch \
  ripgrep \
  openssh-client \
  unzip \
  zip \
  xz-utils \
  python3 \
  sudo \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  locales
rm -rf /var/lib/apt/lists/*
locale-gen ja_JP.UTF-8
update-locale LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8
EOF

RUN git lfs install --system

RUN <<-EOF
ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
git config --system --add safe.directory /workspace
EOF

# Firewall script: root-owned, outside the workspace, so Claude cannot modify it.
# The non-root user may run ONLY this script via sudo; general sudo is removed.
COPY --chown=root:root --chmod=0755 init-firewall.sh /usr/local/bin/init-firewall.sh
RUN <<-EOF
gpasswd -d ubuntu sudo || true
echo "ubuntu ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/firewall
chmod 0440 /etc/sudoers.d/firewall
visudo -cf /etc/sudoers.d/firewall
EOF

USER ubuntu
ENV PATH="/home/ubuntu/.local/bin:${PATH}"

RUN <<-EOF
curl -o ~/.git-prompt.sh https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh
curl -o ~/.git-completion.sh https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash

echo "[ -f ~/.git-prompt.sh ] && source ~/.git-prompt.sh" >> ~/.bashrc
echo "[ -f ~/.git-completion.sh ] && source ~/.git-completion.sh" >> ~/.bashrc
echo "GIT_PS1_SHOWDIRTYSTATE=true" >> ~/.bashrc
echo "GIT_PS1_SHOWUNTRACKEDFILES=true" >> ~/.bashrc
echo "GIT_PS1_SHOWUPSTREAM=auto"  >> ~/.bashrc
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[01;33m\] \w \[\033[01;31m\]\$(__git_ps1 \"(%s)\") \\n+\[\033[01;34m\]\\$ \[\033[00m\]"' >> ~/.bashrc
EOF

RUN curl -fsSL https://claude.ai/install.sh | bash && claude --version

CMD ["bash"]

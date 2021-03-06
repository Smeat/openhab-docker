#!/bin/bash
set -eo pipefail

# Dockerfiles to be generated
versions="2.1.0-snapshot 2.0.0 1.8.3"
arches="amd64 armhf arm64"

# Generate header
print_header() {
	cat > $1 <<-EOI
	# openhab image
	#
	# ------------------------------------------------------------------------------
	#               NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
	#
	#                       PLEASE DO NOT EDIT IT DIRECTLY.
	# ------------------------------------------------------------------------------
	#

	EOI
}

# Print selected image
print_baseimage() {
	# Set download url for openhab version
	case $version in
	2.1.0-snapshot)
		openhab_url="https://openhab.ci.cloudbees.com/job/openHAB-Distribution/lastSuccessfulBuild/artifact/distributions/openhab/target/openhab-2.1.0-SNAPSHOT.zip"
		;;
	2.0.0)
		openhab_url="https://bintray.com/openhab/mvn/download_file?file_path=org%2Fopenhab%2Fdistro%2Fopenhab%2F2.0.0%2Fopenhab-2.0.0.zip"
		;;
	1.8.3)
		openhab_url="https://bintray.com/artifact/download/openhab/bin/distribution-1.8.3-runtime.zip"
		;;
	default)
		openhab_url="error"
		;;
	esac

	# Set java download based on architecture
	case $arch in
	amd64)
		java_url="https://www.azul.com/downloads/zulu/zdk-8-ga-linux_x64.tar.gz"
		;;
	armhf|arm64)
		java_url="https://www.azul.com/downloads/zulu/zdk-8-ga-linux_aarch32hf.tar.gz"
		;;
	default)
		java_url="error"
		;;
	esac
	cat >> $1 <<-EOI
	FROM multiarch/debian-debootstrap:$arch-jessie
	
	# Set download urls
	ENV OPENHAB_URL="$openhab_url"
	ENV JAVA_URL="$java_url"

	EOI
}

# Print metadata && basepackages
print_basepackages() {
	cat >> $1 <<-'EOI'
	# Set variables
	ENV \
	    APPDIR="/openhab" \
	    DEBIAN_FRONTEND=noninteractive \
	    EXTRA_JAVA_OPTS="" \
	    JAVA_HOME='/usr/lib/java-8' \
	    OPENHAB_HTTP_PORT="8080" \
	    OPENHAB_HTTPS_PORT="8443" \
	    USER_ID="9001"

	# Basic build-time metadata as defined at http://label-schema.org
	ARG BUILD_DATE
	ARG VCS_REF
	LABEL org.label-schema.build-date=$BUILD_DATE \
	    org.label-schema.docker.dockerfile="/Dockerfile" \
	    org.label-schema.license="EPL" \
	    org.label-schema.name="openHAB" \
	    org.label-schema.url="http://www.openhab.com/" \
	    org.label-schema.vcs-ref=$VCS_REF \
	    org.label-schema.vcs-type="Git" \
	    org.label-schema.vcs-url="https://github.com/openhab/openhab-docker.git"

	# Install basepackages
	RUN apt-get update && \
	    apt-get install --no-install-recommends -y \
	      ca-certificates \
	      locales \
	      locales-all \
	      libpcap-dev \
	      netbase \
	      unzip \
	      wget \
	      sqlite3 \
	      sqlite \
	      iputils-ping \
	      && rm -rf /var/lib/apt/lists/*

	# Set locales
	ENV \
	    LC_ALL=en_US.UTF-8 \
	    LANG=en_US.UTF-8 \
	    LANGUAGE=en_US.UTF-8

EOI
}

# Print 32-bit for arm64 arch
print_lib32_support_arm64() {
	cat >> $1 <<-'EOI'
	RUN dpkg --add-architecture armhf && \
	    apt-get update && \
	    apt-get install --no-install-recommends -y \
	    libc6:armhf \
	    && rm -rf /var/lib/apt/lists/*

EOI
}

# Install java
print_java() {
	cat >> $1 <<-'EOI'
	# Install java
	RUN wget -nv -O /tmp/java.tar.gz ${JAVA_URL} &&\
	    mkdir ${JAVA_HOME} && \
	    tar -xvf /tmp/java.tar.gz --strip-components=1 -C ${JAVA_HOME} && \
	    update-alternatives --install /usr/bin/java java ${JAVA_HOME}/bin/java 50 && \
	    update-alternatives --install /usr/bin/javac javac ${JAVA_HOME}/bin/javac 50

EOI
}

# Add user and install Openhab
print_openhab_user() {
	cat >> $1 <<-'EOI'
	# Add openhab user & handle possible device groups for different host systems
	# Container base image puts dialout on group id 20, uucp on id 10
	# GPIO Group for RPI access
	RUN adduser -u $USER_ID --disabled-password --gecos '' --home ${APPDIR} openhab &&\
	    groupadd -g 14 uucp2 &&\
	    groupadd -g 16 dialout2 &&\
	    groupadd -g 18 dialout3 &&\
	    groupadd -g 32 uucp3 &&\
	    groupadd -g 997 gpio &&\
	    adduser openhab dialout &&\
	    adduser openhab uucp &&\
	    adduser openhab uucp2 &&\
	    adduser openhab dialout2 &&\
	    adduser openhab dialout3 &&\
	    adduser openhab uucp3 &&\
	    adduser openhab gpio

EOI
}

# Install openhab for 2.0.0 and newer
print_openhab_install() {
	cat >> $1 <<-'EOI'
	# Install openhab
	# Set permissions for openhab. Export TERM variable. See issue #30 for details!
	RUN wget -nv -O /tmp/openhab.zip ${OPENHAB_URL} &&\
	    unzip -q /tmp/openhab.zip -d ${APPDIR} &&\
	    rm /tmp/openhab.zip &&\
	    mkdir -p ${APPDIR}/userdata/logs &&\
	    touch ${APPDIR}/userdata/logs/openhab.log && \
	    cp -a ${APPDIR}/userdata ${APPDIR}/userdata.dist && \
	    cp -a ${APPDIR}/conf ${APPDIR}/conf.dist && \
	    chown -R openhab:openhab ${APPDIR} && \
	    echo "export TERM=dumb" | tee -a ~/.bashrc

EOI
}

# Install openhab for 1.8.3
print_openhab_install_old() {
	cat >> $1 <<-'EOI'
	# Install openhab
	# Set permissions for openhab. Export TERM variable. See issue #30 for details!
	RUN wget -nv -O /tmp/openhab.zip ${OPENHAB_URL} &&\
	    unzip -q /tmp/openhab.zip -d ${APPDIR} &&\
	    rm /tmp/openhab.zip &&\
	    chown -R openhab:openhab ${APPDIR} && \
	    echo "export TERM=dumb" | tee -a ~/.bashrc

EOI
}

# Add volumes for 2.0.0 and newer
print_volumes() {
	cat >> $1 <<-'EOI'
	# Expose volume with configuration and userdata dir
	VOLUME ${APPDIR}/conf ${APPDIR}/userdata ${APPDIR}/addons

EOI
}

# Add volumes for 1.8.3
print_volumes_old() {
	cat >> $1 <<-'EOI'
	# Expose volume with configuration and userdata dir
	VOLUME ${APPDIR}/configurations ${APPDIR}/addons

EOI
}

# Set working directory and execute command
print_command() {
	cat >> $1 <<-'EOI'
	# Execute command
	WORKDIR ${APPDIR}
	EXPOSE 8080 8443 5555
	USER openhab
	CMD ["./start.sh"]

EOI
}

# Build the Dockerfiles
for version in $versions
do
	for arch in $arches
	do
		file=$version/$arch/Dockerfile
			mkdir -p `dirname $file` 2>/dev/null
			echo -n "Writing $file..."
			print_header $file;
			print_baseimage $file;
			print_basepackages $file;
			if [ "$arch" == "arm64" ]; then
				print_lib32_support_arm64 $file;
			fi
			print_java $file;
			print_openhab_user $file;
			if [ "$version" == "1.8.3" ]; then
				print_openhab_install_old $file;
				print_volumes_old $file
			else
				print_openhab_install $file;
				print_volumes $file
			fi
			print_command $file
			echo "done"
	done
done


#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

# Release to install
app_version=2024.1.2

# Requirements
py_required_version=3.12.1
pip_required="pip (>=21.3.1)"

# Fail2ban
failregex="^%(__prefix_line)s.*\[homeassistant.components.http.ban\] Login attempt or request with invalid authentication from.* \(<HOST>\).* Requested URL: ./auth/.*"

#=================================================
# PERSONAL HELPERS
#=================================================

# Check if directory/file already exists (path in argument)
myynh_check_path () {
	[ -z "$1" ] && ynh_die "No argument supplied"
	[ ! -e "$1" ] || ynh_die "$1 already exists"
}

# Create directory only if not already exists (path in argument)
myynh_create_dir () {
	[ -z "$1" ] && ynh_die "No argument supplied"
	[ -d "$1" ] || mkdir -p "$1"
}

# Install specific python version
# usage: myynh_install_python --python="3.8.6"
# | arg: -p, --python=    - the python version to install
myynh_install_python () {
	# Declare an array to define the options of this helper.
	local legacy_args=u
	local -A args_array=( [p]=python= )
	local python
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	
	# Check python version from APT
	local py_apt_version=$(python3 --version | cut -d ' ' -f 2)
	
	# Usefull variables
	local python_major=${python%.*}
	
	# Check existing built version of python in /usr/local/bin
	if [ -e "/usr/local/bin/python$python_major" ]
	then
		local py_built_version=$(/usr/local/bin/python$python_major --version \
			| cut -d ' ' -f 2)
	else
		local py_built_version=0
	fi
	
	# Compare version
	if $(dpkg --compare-versions $py_apt_version ge $python)
	then
		# APT >= Required
		ynh_print_info --message="Using provided python3..."
		
		py_app_version="python3"
		
	else
		# Either python already built or to build 
		if $(dpkg --compare-versions $py_built_version ge $python)
		then
			# Built >= Required
			ynh_print_info --message="Using already used python3 built version..."
			
			py_app_version="/usr/local/bin/python${py_built_version%.*}"
			
		else
			# APT < Minimal & Actual < Minimal => Build & install Python into /usr/local/bin
			ynh_print_info --message="Building python (may take a while)..."
			
			# Store current direcotry 
			local MY_DIR=$(pwd)
			
			# Create a temp direcotry
			tmpdir="$(mktemp --directory)"
			cd "$tmpdir"
			
			# Download
			wget --output-document="Python-$python.tar.xz" \
				"https://www.python.org/ftp/python/$python/Python-$python.tar.xz" 2>&1
			
			# Extract
			tar xf "Python-$python.tar.xz"
			
			# Install
			cd "Python-$python"
			./configure --enable-optimizations
			ynh_exec_warn_less make -j4
			ynh_exec_warn_less make altinstall
			
			# Go back to working directory
			cd "$MY_DIR"
			
			# Clean
			ynh_secure_remove "$tmpdir"
			
			# Set version
			py_app_version="/usr/local/bin/python$python_major"
		fi
	fi
	# Save python version in settings 
	ynh_app_setting_set --app=$app --key=python --value="$python"
}
	
myynh_install_homeassistant () {
	# Create the virtual environment
	ynh_exec_as $app $py_app_version -m venv --without-pip "$install_dir"
	
	# Run source in a 'sub shell'
	(
		# activate the virtual environment
		set +o nounset
		source "$install_dir/bin/activate"
		set -o nounset
		
		# add pip
		ynh_exec_as $app "$install_dir/bin/python3" -m ensurepip
  
  		if [ $YNH_ARCH == "armhf" ] || [ $YNH_ARCH == "armel" ]
		then
			# Install rustup is not already installed
			# We need this to be able to install cryptgraphy
			export PATH="$PATH:$install_dir/.cargo/bin:$install_dir/.local/bin:/usr/local/sbin"
			if [ -e $install_dir/.rustup ]; then
				sudo -u "$app" env PATH=$PATH rustup update
			else
				sudo -u "$app" bash -c 'curl -sSf -L https://static.rust-lang.org/rustup.sh | sh -s -- -y --default-toolchain=stable --profile=minimal'
			fi
		fi  
   		# install last version of pip
		ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "$pip_required"

  		# install last version of wheel
		ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade wheel

		# install last version of setuptools
		ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade setuptools

		# install last version of wheel
		#ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade cmake

  		if [ $YNH_ARCH == "armhf" ] || [ $YNH_ARCH == "armel" ]
		then
			# Install last version of PyNacl  
   			# Because of error on post install : "Unable to set up dependencies of default_config. Setup failed for dependencies: mobile_app "
			ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade PyNacl
   
			# install last version of numpy (https://github.com/numpy/numpy/issues/24703)
			ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "numpy>=1.21.2" --config-settings=setup-args="-Dallow-noblas=true"


      
			# install last version of numpy (https://github.com/numpy/numpy/issues/24703)
			ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "aiohttp>=3.9.1" 

   		    # only if camera related services used:
			# install last version of PyNacl (need cmake installed)
			ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "PyTurboJPEG>=1.7.3"
						
   			# need to recompile ffmpeg https://community.home-assistant.io/t/unable-to-install-package-ha-av/466286/31
    			ynh_secure_remove "$data_dir/.cache/FFmpeg"
       			ynh_exec_warn_less git config --global --unset http.extraheader
       			ynh_exec_warn_less git config --global --unset http.postbuffer
       			ynh_exec_warn_less git config --global --unset http.version
       			ynh_exec_warn_less git config --global --unset http.sslverify
			ynh_exec_warn_less git clone --branch release/6.0 --depth 1 https://github.com/FFmpeg/FFmpeg.git "$data_dir/.cache/FFmpeg"
			
			cd "$data_dir/.cache/FFmpeg"
			./configure \
			    --extra-cflags="-I/usr/local/include" \
			    --extra-ldflags="-L/usr/local/lib" \
			    --extra-libs="-lpthread -lm -latomic" \
			    --arch=armel \
			    --enable-gmp \
			    --enable-gpl \
			    --enable-libass \
			    --enable-libdrm \
			    --enable-libfreetype \
			    --enable-libmp3lame \
			    --enable-libopencore-amrnb \
			    --enable-libopencore-amrwb \
			    --enable-libopus \
			    --enable-librtmp \
			    --enable-libsnappy \
			    --enable-libsoxr \
			    --enable-libssh \
			    --enable-libvorbis \
			    --enable-libwebp \
			    --enable-libx264 \
			    --enable-libx265 \
			    --enable-libxml2 \
			    --enable-nonfree \
			    --enable-version3 \
			    --target-os=linux \
			    --enable-pthreads \
			    --enable-openssl \
			    --enable-hardcoded-tables \
			    --enable-pic \
			    --disable-static \
			    --enable-shared
				
			ynh_exec_warn_less make -j$(nproc)
			ynh_exec_warn_less make install
			ynh_exec_warn_less ldconfig
	   		ynh_exec_warn_less cp "$data_dir/.cache/FFmpeg"/ffmpeg /usr/bin/
	    
		fi
  
		ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "pybase64"
		
  		# install last version of ninja (needed by cmake)
		#ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "ninja>=1.11.1.1"
		#ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade ha-av
		#ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "opencv-python-headless"
  		#ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "tflite-support==0.4.2"
		#ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "tflite-runtime==2.11.0"
		
  		# install last version of mysqlclient
		ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade mysqlclient
		
		# install Home Assistant
		ynh_exec_warn_less ynh_exec_as $app "$install_dir/bin/pip3" --cache-dir "$data_dir/.cache" install --upgrade "$app==$app_version"
	)
}

# Upgrade the virtual environment directory
myynh_upgrade_venv_directory () {
	
	# Remove old python links before recreating them
	find "$install_dir/bin/" -type l -name 'python*' \
		-exec bash -c 'rm --force "$1"' _ {} \;
	
	# Remove old python directories before recreating them
	find "$install_dir/lib/" -mindepth 1 -maxdepth 1 -type d -name "python*" \
		-not -path "*/python${py_required_version%.*}" \
		-exec bash -c 'rm --force --recursive "$1"' _ {} \;
	#find "$install_dir/include/site/" -mindepth 1 -maxdepth 1 -type d -name "python*" \
	#	-not -path "*/python${py_required_version%.*}" \
	#	-exec bash -c 'rm --force --recursive "$1"' _ {} \;

	# Upgrade the virtual environment directory
	ynh_exec_as $app $py_app_version -m venv --upgrade "$install_dir"
}

# Set permissions
myynh_set_permissions () {
	chown -R $app: "$install_dir"
	chmod 750 "$install_dir"
	chmod -R o-rwx "$install_dir"

	chown -R $app: "$data_dir"
	chmod 750 "$data_dir"
	chmod -R o-rwx "$data_dir"
	[ ! -e "$data_dir/bin/" ] || chmod -R +x "$data_dir/bin/"

	[ ! -e "$(dirname "$log_file")" ] || chown -R $app: "$(dirname "$log_file")"

	[ ! -e "/etc/sudoers.d/$app" ] || chown -R root: "/etc/sudoers.d/$app"
}

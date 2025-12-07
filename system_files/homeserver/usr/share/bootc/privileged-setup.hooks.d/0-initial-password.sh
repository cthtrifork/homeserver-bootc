
if  [ ! -e /etc/passwd.done ]; then
  echo "Password" | passwd $USER_NAME -s
fi

touch  /etc/passwd.done

# lock out root user
if ! usermod -L root; then
	sed -i 's|^root.*|root:!:1::::::|g' /etc/shadow
fi

#!/bin/bash

type docker

if [ $? -ne 0 ]; then
	bundle exec jekyll serve --host=0.0.0.0 --drafts
	echo 'open brower vist http://localhost:4000'
else
	container=$(sudo docker ps -a | grep 'blog_web' | grep -oP '\S+' | head -1)

	if [ -z "$container" ]; then
		sudo docker run -it -p 4000:4000 --name blog_web --volume="$PWD:/srv/jekyll" jekyll/jekyll jekyll server --watch
		echo 'open brower vist http://localhost:4000'
	else
		sudo docker start $container
		sudo docker attach $container
	fi
fi


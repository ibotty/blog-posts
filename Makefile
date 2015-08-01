updateReadme: clean_working_dir Readme.md 
	git add Readme.md
	git commit -m 'update Readme'
	git push

Readme.md: */*/*/*.md Readme.head.md
	cat Readme.head.md > Readme.md
	find 2* -name \*.md  | sort -r | xargs -d\\n sh -c 'echo " * [$$0]($$0)"' >> Readme.md

*.md:


clean_working_dir:
	git diff-index --quiet HEAD || (echo "Working directory unclean. Please commit."; exit 1)


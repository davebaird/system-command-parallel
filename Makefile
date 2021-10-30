
readme:
	perl -MPod::Markdown -e 'Pod::Markdown->new->filter(@ARGV)' lib/System/Command/Parallel.pm > README.md

#!/usr/bin/env perl
#
# gstack-dumper: gstack dump for cpu consuming processes
# 20 Mar 2020
# Chul-Woong Yang
#
use strict;
use warnings;
use Getopt::Long;

$| = 1; # enable command buffering, that is line buffering.

sub prog_exists {
    my $prog = shift;
    system("which $prog > /dev/null 2>&1") == 0;
}
sub mkdir_p {
    my $dir = shift;
    system("mkdir -m 700 -p $dir > /dev/null 2>&1") == 0;
}

(my $progname = $0) =~ s|^.*/||;
    
my $opt_help;
my ($outdir, $interval, $start_at, $max_num, $threshold);
my $d;

$outdir = "/var/log/gstack";
$interval = 5;
$start_at = 3;
$max_num = 5;
$threshold = 95;

GetOptions(
    "outdir=s"		=> \$outdir,
    "interval=i"	=> \$interval,
    "start=i"		=> \$start_at,
    "max_num=i"		=> \$max_num,
    "threshold=i"	=> \$threshold,
    help		=> \$opt_help,
) or exit 1;
if ($opt_help) {
    print << "EOT";
Usage: $progname [options] program_to_watch

Options:
  --outdir <dir>	directory to dump gstack results
  --interval <minutes>	cpu utilization check interval in minutes	(def: 5)
  --start <num>		number of consecutive high-loads to start dump	(def: 3)
  --max <num>		maximum number of dump files for each thread	(def: 5)
  --threshold <num>	CPU utilization to trigger event		(def: 95)
  --help		print this help

The command tracks given programs and dumps gstack result of running process
when the thread cpu utilization is over 95% for specified periods.
EOT
    exit 0;
}

die "no program to watch\n" if @ARGV == 0;
my $prog_to_watch = shift;

die "gstack not found\n" unless prog_exists("gstack");
die "ps not found\n" unless prog_exists("ps");

die "cannot write to $outdir\n" unless mkdir_p("$outdir");

print "\u$progname starts monitoring <$prog_to_watch> each $interval minutes.\n";
print "When $start_at consecutive high load (CPU >= $threshold%) threads are detected,"
    . " it calls gstack $max_num times with 1 minute interval and logs the results.\n";

my $cmd = "ps -C $prog_to_watch -Lo pcpu,psr,pid,tid,cputime,s,comm\n";
my (%procs, %dump_count);

for (;;) {
    my @output = `$cmd`;
    my $date = `date`;
    my %targets = filter_target(@output);
    die "\u$progname stops monitoring <$prog_to_watch>\n"
	if getppid == 1;	# calling script dies

    for my $tid (keys %procs) {
	delete $procs{$tid} unless exists $targets{$tid} 
    }

    my $dumped = 0;
    for my $tid (keys %targets) {
	if (($dump_count{$tid} // 0) >= $max_num) {
	    next;
	}
	print "thread $tid has high load (>= $threshold%)\n";
    
	if (++$procs{$tid} >= $start_at) {
	    dump_gstack($targets{$tid}, $date, \@output, ++$dump_count{$tid});
	    $dumped = 1;
	}
    }
    if ($dumped) {
	sleep 60;
    } else {
	sleep $interval * 60;
    }
}
#print "hi $prog $prog2\n"

sub filter_target {
    shift;
    map {
	my @a = split ' ';
	$a[3] => $a[2];	# (tid => pid)
    }
    grep {
	(split ' ')[0] >= $threshold;
    }
    sort {
	(split(' ', $b))[0] <=> (split(' ', $a))[0];
    } @_;
}

sub dump_gstack {
    my ($pid, $date, $output_ref, $no) = @_;
    my $gstack = `gstack $pid`;
    my $dest = $prog_to_watch;
    $dest =~ s|/|_|g;

    print "dumping high-load process info to $outdir/$dest.$pid.log ($no/$max_num)\n";
    if (open DUMPFILE, ">>", "$outdir/$dest.$pid.log") {
	print DUMPFILE $date;
	print DUMPFILE @$output_ref;
	print DUMPFILE $gstack;
	print DUMPFILE "--------------------------------------------------------------\n";
    }
}

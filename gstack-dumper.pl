#!/usr/bin/env perl
#
# run_gstack: gstack dump for cpu consuming processes
# 20 Mar 2020
# Chul-Woong Yang
#
use strict;
use warnings;
use Getopt::Long;

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
$max_num = 3;
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
  --start <num>		number of consecutive events to start dump	(def: 3)
  --max <num>		maximum number of dump files for each process	(def: 3)
  --threshold <num>	CPU utilization to trigger event		(def: 95)
  --help		print this help

The command tracks given programs and dumps gstack result of running process
when the process cpu utilization is over 95% for specified periods.
EOT
    exit 0;
}

die "no program to watch\n" if @ARGV == 0;
my $prog_to_watch = shift;

die "gstack not found\n" unless prog_exists("gstack");
die "ps not found\n" unless prog_exists("ps");

die "cannot write to $outdir\n" unless mkdir_p("$outdir");

print "\u$progname start monitoring <$prog_to_watch> each $interval minutes.\n";
print "When $start_at consecutive high load (CPU >= $threshold%) events are detected,"
    . " it stores gstack dumpfiles to $outdir, upto $max_num per each process.\n";

my $cmd = "ps -C $prog_to_watch -Lo pcpu,psr,pid,tid,cputime,s,comm\n";
my %procs;

for (;;) {
    my @output = `$cmd`;
    my $date = `date`;
    my %targets = filter_target(@output);
    print @output;
    
    for my $pid (keys %procs) {
	delete $procs{$pid} unless exists $targets{$pid} 
    }
    for my $pid (keys %targets) {
	if (++$procs{$pid} >= $start_at) {
	    dump_gstack($pid, $date, \@output);
	}
    }
    sleep 5;
}
#print "hi $prog $prog2\n"

sub filter_target {
    shift;
    map {
	(split ' ')[2] => 1;	# pid
    }
    grep {
	(split ' ')[0] >= $threshold;
    }
    sort {
	(split(' ', $b))[0] <=> (split(' ', $a))[0];
    } @_;
}

sub dump_gstack {
    my ($pid, $date, $output_ref) = @_;
    my $gstack = `gstack $pid`;
    my $dest = $prog_to_watch;
    $dest =~ s|/|_|g;

    print "dumping high-load process info to $outdir/$dest.$pid.log\n";
    if (open DUMPFILE, ">>", "$outdir/$dest.$pid.log") {
	print DUMPFILE $date;
	print DUMPFILE @$output_ref;
	print DUMPFILE $gstack;
	print DUMPFILE "--------------------------------------------------------------\n";
    }
}

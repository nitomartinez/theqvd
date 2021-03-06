package QVD::CommandInterpreter;

use strict;
use warnings;
use Log::Log4perl;


=head1 NAME

QVD::CommandInterpreter - Command interpreter for serial port forwarding

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';


=head1 SYNOPSIS

Safetly runs socat for serial port forwarding. Expected to be extended
for other functions in the future.

This module is used by the commandline B<qvdcmd.pl> application.

=head1 EXAMPLE

 $ ./qvdcmd.pl
                                                                                                                                                                                  
 > version
 0.01
                                                                                                                                                                                  
 > socat /dev/ttyS0

=head1 SUBROUTINES/METHODS


=head2 new( config => $config, options => $options )

Creates the QVD::CommandInterpreter. Optionally takes a hash as an argument:

 my $cmd = new QVD::CommandInterpreter( config = $config, options = $options )

Where:

$config is the configuration file, with the following stucture:

 my $config = {
 	socat => '/usr/bin/socat',
        pppd  => '/usr/sbin/pppd',
 	allowed_ports => [ qr#^/dev/ttyS\d+#,
 	                   qr#^/dev/ttyUSB/\d+# ]
 };

$options are command-line options, currently:

 my $options = {
 	debug => $debug
 }


=cut

sub new {
	my ($class, %args) = @_;
	my $self = {};

	bless $self, $class;

	$self->{log} = Log::Log4perl->get_logger('QVD::CommandInterpreter');

	$self->{commands} = {
		version => \&cmd_version,
		help    => \&cmd_help,
		quit    => \&cmd_quit,
		socat   => \&cmd_socat,
		pppd    => \&cmd_pppd
	};

	$self->{config} = {
		socat => '/usr/bin/socat',
		pppd  => '/usr/sbin/pppd',
		allowed_ports => [ qr#^/dev/ttyS\d+#,
		                   qr#^/dev/ttyUSB/\d+#,
		                   qr#^/dev/ttyUSB\d+#,
		                   qr#^/dev/ttyACM\d+#,
		                   qr#^/dev/usblp\d+#]
	};

	foreach my $key (keys %args) {
		$self->{$key} = $args{$key};
	}
	
	return $self;
}

=head2 run

Reads and executes commands from stdin until done

=cut

sub run {
	my ($self) = @_;

	undef $self->{done};

	while(!$self->{done}) {
		$self->_out( "\n> " );
		my $line = <>;
		last unless ($line);

		chomp $line;
		my ($command, @args) = split(/\s+/, $line);
		next unless ($command);
	
		$self->run_command($command, @args);
	}
	return;
}

=head2 run_command($command, @args)

Executes a single command with the specified arguments

=cut

sub run_command {
	my ($self, $command, @args) = @_;
	if ( exists $self->{commands}->{$command} ) {
		$self->{log}->debug("Command: $command " . join(' ', @args));
		$self->{commands}->{$command}->($self, @args);
	} else {
		$self->_err("ERROR: Unknown command '$command'. Try 'help'.\n");
	}
	return;
}


=head1 COMMANDS

These are the commands the interpreter implements

=cut

=head2 cmd_help

Shows the help

=cut

sub cmd_help {
	my ($self, @args) = @_;

	$self->_out("Commands:\n");
	$self->_out("\thelp          Shows this help\n");
	$self->_out("\tsocat <port>  Connects socat on the indicated port\n");
	$self->_out("\tpppd arg1 ..  pppd with the given args\n");
	$self->_out("\tquit          Quits the interpreter\n");
	$self->_out("\tversion       Shows the version number\n");
	return;
}

=head2 cmd_quit

Quits the interpreter if called from whithin L</run>

=cut

sub cmd_quit {
	my ($self, @args) = @_;
	$self->{log}->info("Quit command received");
	$self->_out("Bye.\n");
	$self->{done} = 1;
	return;
}


=head2 cmd_socat( $port )

Runs socat on the indicated $port.

Performs checks to ensure the port is allowed and exists.

If the checks succeed, runs socat to connect the indicated port with stdin. At
that point, the interpreter uses 'exec' to call socat, and no more commands
are possible.

=cut

sub cmd_socat {
	my ($self, @args) = @_;

	my $port = $args[0];
	my $cport = $self->_check_port($port);

	if ( !$cport ) {
		$self->_err("ERROR: Port '$port' is not allowed\n");
	} else {
		if ( ! -e $cport ) {
			$self->_err("ERROR: Port '$port' doesn't exist\n");
		} else {
			my @extra_args;
			if ( $self->{debug} ) {
				push @extra_args, "-v", "-lf/tmp/qvdcmd-socat.log";
			}

			$self->{log}->info("Starting socat on port $cport");
			$self->_out("OK\n");
			exec($self->{config}->{socat}, @extra_args, "-", "$cport,nonblock,raw,echo=0");
		}
	}
	return ;
}


=head2 cmd_pppd( @args )

Runs pppd with specified args

=cut

sub cmd_pppd {
	my ($self, @args) = @_;

	my @full_args = $self->_check_pppd_args(@args);
	if (!@full_args) {
	    $self->_err("ERROR: pppd args do not comply with character constraints");
	    return;
	}
	# FIXME do not start pppd if full_args is empty
	if ( $self->{debug} ) {
	    push @full_args, "debug";
	}
	$self->{log}->info("Starting pppd with args: ", join(" ", @full_args));
	$self->_out("OK\n");
	exec($self->{config}->{pppd}, @full_args);
}


=head2 cmd_version

Returns the module's version

=cut

sub cmd_version {
	my ($self, @args) = @_;

	$self->_out("$VERSION\n");
	return;
}

# FIXME get this also in config
sub _check_pppd_args {
	my ($self, @args) = @_;
	my @result;
	foreach my $arg ( @args ) {
	    if ($arg =~ qr#([-a-zA-Z0-9:,/]+)#x) {
		push @result, $1;
	    } else {
		print STDERR "check_pppd_args: Argument <$arg> does not match constraints returning non arg";
		$self->{log}->error("check_pppd_args: Argument <$arg> does not match constraints returning non arg");
		return ();
	    }
	}

	return @result;
}


sub _check_port {
	my ($self, $port) = @_;
	foreach my $reg ( @{$self->{config}->{allowed_ports}} ) {
	    if ( $port =~ m/($reg)/x ) {
		return $1;
	    }
	}

	return ();
}

sub _out {
	my ($self, $msg) = @_;
	print $msg;
	return;
}

sub _err {
	my ($self, $msg) = @_;
	$self->{log}->error($msg);
	print $msg;
	return;
}

=head1 SEE ALSO

L<QVD::CommandInterpreter::Client>

=head1 AUTHOR

QVD Team, C<< <qvd at qindel.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-qvd-commandinterpreter at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=QVD-CommandInterpreter>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc QVD::CommandInterpreter


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=QVD-CommandInterpreter>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/QVD-CommandInterpreter>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/QVD-CommandInterpreter>

=item * Search CPAN

L<http://search.cpan.org/dist/QVD-CommandInterpreter/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 QVD Team.

This program is released under the following license: GPL3


=cut

1; # End of QVD::CommandInterpreter

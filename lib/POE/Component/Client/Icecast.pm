package POE::Component::Client::Icecast;
use strict;
use warnings;

use Carp 'carp', 'croak';
use POE::Session;
use POE::Filter::Stream;
use POE::Component::Client::TCP;

use constant TRACE => $ENV{'ICECAST_TRACE'} || 0;
use constant DEBUG => $ENV{'ICECAST_DEBUG'} || 0;

our $VERSION = 0.12;

sub new {
	my $type   = shift;
	my $param  =  {@_};
	
	my $mi     = $type.'->new()'; # hi, Rocco Caputto!
	croak "$mi requires an even number of parameters" if @_ & 1;
	
	my $agent  = join('/', __PACKAGE__, $VERSION);
	my $stream = $param->{'Stream'} ? _parse_stream_param($param->{'Stream'}) : {};
	
	my $host   = $stream->{'Host'} || $param->{'Host'} || croak "$mi requires Host param to stream";
	my $path   = $stream->{'Path'} || $param->{'Path'} || croak "$mi requires Path param to stream";
	   $path   = "/$path" unless $path =~ m{^/};
	
	POE::Component::Client::TCP->new(
		(map { $_ => $stream->{$_} || $param->{$_} } 'RemoteAddress', 'RemotePort', 'BindAddress', 'BindPort'),
		
		'Filter'        => POE::Filter::Stream->new,
		'Connected'     => sub {
			$_[HEAP]->{'server'}->put(grep { DEBUG && warn $_;1 } join "\n",
				"GET $path HTTP/1.0",
				"Host: $host",
				"User-Agent: $agent",
				'Accept: */*',
				'Icy-MetaData: 1',
				'Connection: close',
				('') x 2
			);
		},
		
		'ServerInput'   => sub {
			DEBUG && warn 'Server input ' . length $_[ARG0];
			return unless my %tag = $_[ARG0] =~ /Stream(\w+)=([^;]+)/g;
			DEBUG && warn $tag{'Title'};
			
			{
				local $_[ARG0] = \%tag;
				ref $param->{'GetTags'} eq 'CODE' && $param->{'GetTags'}->(@_);
			}
		},
		
		'Disconnected'  => sub {
			DEBUG && warn "$mi disconnected";
			
			if ($param->{'Reconnect'}) {
				DEBUG && warn "$mi will reconnect, delay is $param->{'Reconnect'}";
				$_[KERNEL]->delay('reconnect' => $param->{'Reconnect'});
			}
		},
		
		'ConnectError'  => sub { croak "$mi has connect error:  ", join('  ', @_[ARG0..$#_]) },
		'ServerError'   => sub { carp  "$mi has server  error:  ", join('  ', @_[ARG0..$#_]) },
		
		'SessionParams' => [ 'options' => { 'trace' => TRACE } ],
	) or croak "$mi has error: $!";
}

#

sub _parse_stream_param {
	my $stream = shift || return {};
	
	my($domain, $path) = $stream =~ m{^ http :// ([^/]+) / (.*) }x;
	my($addr,   $port) = $domain =~ m{^ (.*) : (.*) }x;
	
	return {
		'Host'          => $addr,
		'RemoteAddress' => $addr,
		'RemotePort'    => $port || 80,
		'Path'          => $path,
	};
}

1;

__END__
=head1 NAME

POE::Component::Client::Icecast - non-blocking client to Icecast server for getting tags

=head1 SYNOPSIS

    use strict;
    use POE qw(Component::Client::Icecast);
    use Data::Dumper;
    
    POE::Component::Client::Icecast->new(
        Stream    => 'http://station20.ru:8000/station-128',
        Reconnect => 10,
        GetTags   => sub {
            warn Dumper $_[ARG0];
        },
    );
    
    # or
    
    POE::Component::Client::Icecast->new(
        Host          => 'station20.ru',
        Path          => '/station-128',
        
        RemoteAddress => '87.242.82.108',
        RemotePort    => 8000,
        BindPort      => 8103, # for only one permanent client
        
        Reconnect     => 10,
        
        GetTags       => sub {
            warn Dumper $_[ARG0];
        },
    );
    
    POE::Kernel->run;


=head1 DESCRIPTION

The module is a non-blocking client to Icecast streaming multimedia server for getting stream tags.

See L<http://www.icecast.org/>.

POE::Component::Client::Icecast is based on L<POE::Component::Client::TCP>.

=head1 METHODS

=head2 new


    POE::Component::Client::Icecast->new(
        Stream        => 'http://station20.ru:8000/station-128',
        
        # or
        
        Host          => 'station20.ru',
        Path          => '/station-128',
        
        RemoteAddress => '87.242.82.108',
        RemotePort    => 8000,
        BindPort      => 8103, # for only one permanent client
        
        # get tags from server
        
        GetTags => sub {
            warn Dumper $_[ARG0];
        },
    );

PoCo::Client::Icecast's new method takes a few named parameters:

=over 9

=item * I<Stream>

The stream url to Icecast stream, which contains domain, port and path to stream. Recommended.

Instead of this param you ought to use: I<Host>, I<Path>, I<RemoteAddr> and I<RemotePort>.

=item * I<Host>

The host of Icecast server (without port).

=item * I<Path>

The path to Icecast stream.

=item * I<RempoteAddress>

The remote address to connect to Icecast server (host or ip).
It's a param of L<POE::Component::Client::TCP>.

=item * I<RemotePort>

The remote port to connect.
It's a param of L<POE::Component::Client::TCP>.

=item * I<BindAddress>

The param specifies the local interface address to bind to before starting to connect.
It's a param of L<POE::Component::Client::TCP>.

=item * I<BindPort>

The param sets the local socket port that the client will be bound to before starting to connect.
It's a param of L<POE::Component::Client::TCP>.

=item * I<GetTags>

The event of getting tags from server, it is called for each fully parsed input record from Icecast server.

I<$_[ARG0]> contains a hashref of tags.

=item * I<Reconnect>

The flag of reconnect to Icecast server. If this flag exists, client will reconnect to server when an established socket has been disconnected.
Delay is value of this param (in seconds). Default value is 0 (no reconnect).

=back


=head1 DEBUG & TRACE MODES

The module supports debug mode and trace mode (trace POE session).

    BEGIN { $ENV{ICECAST_DEBUG}++; $ENV{ICECAST_TRACE}++ };
    use POE::Component::Client::Icecast;

=head1 EXAMPLES

See I<examples/test.pl> in this distributive.


=head1 SEE ALSO

L<POE>

=head1 DEPENDENCIES

L<POE::Component::Client::TCP> L<POE::Filter::Stream> L<POE::Session> L<Carp>

=head1 AUTHOR

Anatoly Sharifulin, C<< <sharifulin at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-poe-component-client-icecast at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=poe-component-client-icecast>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT & DOCUMENTATION

You can find documentation for this module with the perldoc command.

    perldoc POE::Component::Client::Icecast

You can also look for information at:

=over 5

=item * Github

L<http://github.com/sharifulin/poe-component-client-icecast/tree/master>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=poe-component-client-icecast>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/poe-component-client-icecast>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/poe-component-client-icecast>

=item * Search CPAN

L<http://search.cpan.org/dist/poe-component-client-icecast>

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Anatoly Sharifulin

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

package Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::CreateLetters;

use Modern::Perl;
use POSIX qw(strftime);
use PDF::API2;

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Format::PDF qw(toPDF getNumberOfPages setMediaboxByPage);
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::DispatchXML qw(DispatchXML);
use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Deliver::File qw(WriteiPostArchive WriteiPostPDF);

use Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config;

use Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database;

# Constructor
sub new {
    my ($class, $params) = @_;
    my $self = {};
    $self->{type} = $params->{type};
    $self->{interface} = $params->{interface};
    $self->{branch} = $params->{branch};
    $self->{testID} = $params->{testID};
    $self->{types} = ['pdf', 'ipost_pdf'];
    bless $self, $class;
    return $self;
}

sub interface {
    my ($self) = @_;
    return $self->{interface};
}

sub branch {
    my ($self) = @_;
    return $self->{branch};
}

sub type {
    my ($self) = @_;
    return $self->{type};
}

sub types {
    my ($self) = @_;
    return @{$self->{types}};
}

sub testID {
    my ($self) = @_;
    return $self->{testID};
}

sub config {
    my ($self) = @_;
    return Koha::Plugin::Fi::KohaSuomi::KSMessaging::Modules::Config->new({
        interface => $self->interface,
        branch => $self->branch,
    });
}

# Public method to create letters
sub create_ipost_letter {
    my ($self, $message) = @_;

    die "Type not supported" unless grep { $_ eq $self->type } $self->types;
    die "No iPost configuration found for ".$self->branch unless $self->config->getIPostConfig;

    my $senderid = $self->config->getIPostConfig->{senderid};

    die "Mandatory parameter senderid is not set for branch." unless ( $senderid );

    # Set fileprefix same as senderid or override if prefix is set in config
    my $fileprefix=$senderid;
    $fileprefix= $self->config->getIPostConfig->{fileprefix} if ( $self->config->getIPostConfig->{fileprefix} );

    # Define filename
    my $filename = $fileprefix . "_";

    # Run time backwards to make suomi.fi happy with our filenames
    my $pseudotime=time();
    $pseudotime--;
    $filename .= strftime( "%Y%m%d%H%M%S", localtime($pseudotime) );
    
    return $self->create_pdf($message, $filename) if $self->type eq 'pdf';
    return $self->create_ipost_pdf($message, $filename) if $self->type eq 'ipost_pdf';
}

sub create_pdf {
    my ($self, $message, $filename) = @_;
    
    $filename .= ".pdf";
    WriteiPostPDF ( 'interface' => $self->interface, 'branchconfig' => $self->config->branchConfig(), 'pdf' => toPDF ( %{$message} ), 'filename' => $filename );
    return $filename;
}

sub create_ipost_pdf {
    my ($self, $message, $filename) = @_;
    
    my $pdfname = @$message{'message_id'} . '.pdf';
    #my $formattedmessage = setMediaboxByPage ( toPDF ( %{$message} ) );
    my $formattedmessage = toPDF ( %{$message} );
    my $dispatch = @$message{'message_id'} . '.xml';

    my $ssndb = Koha::Plugin::Fi::KohaSuomi::SsnProvider::Modules::Database->new();
    my $ssn = $self->testID || eval {$ssndb->getSSNByBorrowerNumber ( @$message{'borrowernumber'} )};
    if ( $@ ) {
        print STDERR "Error getting SSN for borrower number " . @$message{'borrowernumber'} . ": $@";
    }

    unless ( $ssn ) {
        $filename .= "_suoratulostus";
    }
    $filename .= '_' . $self->config->getIPostConfig->{printprovider} if ( $self->config->getIPostConfig->{printprovider} );
    $filename .= ".zip";
    my $dispatchXML = DispatchXML ( 'interface'      => $self->interface,
                                    'borrowernumber' => @$message{'borrowernumber'},
                                    'SSN'            => $ssn || 'N/A', # 'N/A' is a placeholder for 'no SSN available
                                    'filename'       => $pdfname,
                                    'branchconfig'   => $self->config->branchConfig(),
                                    'letterid'       => @$message{'message_id'},
                                    'subject'        => @$message{'subject'},
                                    'totalpages'     => getNumberOfPages($formattedmessage) );

    # Debug
    if ( $ENV{'DEBUG'} && $ENV{'DEBUG'} == 1 ) {
        print STDERR "\n=== Message " . @$message{'message_id'} . " handled for branch 'default', binary format (PDF) only dispatch data shown ===\n\n";
        print STDERR $dispatchXML;
    }

    # Put files in an iPostPDF archive
    WriteiPostArchive ( 'interface'    => $self->interface,
                        'pdf'          => $formattedmessage,
                        'xml'          => $dispatchXML,
                        'pdfname'      => $pdfname,
                        'xmlname'      => $dispatch,
                        'branchconfig' => $self->config->branchConfig(),
                        'filename'     => $filename );
    return $filename;
}

1;
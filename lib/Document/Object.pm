
=head1 NAME

Document::Object

=head1 SYNOPSIS

my $doc = new Document::Object;

$doc->state($state, $comment);

my $cid = $doc->comment( undef,
			 { author => "Me",
			   subject => "My Subject",
			   text => "Comment to be appended"
			   }
			 );
my @comments = $doc->comment();
my $comment = $doc->comment(42);

my $text = $doc->diff($revA, $revB);

my $wid = $doc->watcher( undef,
			 { name => "Me",
			   email => "myself@mydomain.com"
			   }
			 );

=head1 DESCRIPTION

This class encapsulates information about a generic document and
operations for altering its properties.  A document is assumed to be a
collection of one or more files, with metadata.

=head1 FUNCTIONS

=cut

package Document::Object;

use strict;
use Document::Repository;
use RDF::Simple;

use vars qw($VERSION %FIELDS);
our $VERSION = '0.10';

use fields qw(
	      _repository
	      _doc_id
	      _metadata
	      _STATES
	      );

=head2 new()

Creates a new document object.

=cut

sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = bless [\%FIELDS], $class;

    # TODO:  Flesh this out
    $self->{'_repository'} = $args{'repository'};
    $self->{'_doc_id'} = $args{'doc_id'};
    $self->{'_STATES'} = { 'new' => 1,
			   'open' => 1,
			   'accepted' => 1,
			   'rejected' => 1,
			   'problem' => 1
			   };

    return $self;
}

sub _set_error {
    my $self = shift;
    $self->{_error_msg} = shift;
}

=head2 get_error()

Retrieves the most recent error message

=cut

sub get_error {
    my $self = shift;
    return $self->{_error_msg};
}


=head2 log

Gets or adds comments in change log

=cut

sub log {
    my $self = shift;
    my $comment = "";

    return $comment;
}

=head2 content($filename[, $content])

Retrieves the contents of a file in the document from the repository,
or, if $content is defined, stores the content into the file.

=cut

sub content {
    my $self = shift;
    my $filename = shift || return undef;
    my $content = shift;

    if (! defined $self->{'_repository'}) {
	$self->set_error("Repository not defined in content()\n");
	return undef;
    }

    if (! $self->{_doc_id}) {
	$self->set_error("document id not defined in content()\n");
	return undef;
    }

    if (defined $content) {
	return $self->{'_repository'}->update($filename,
					      $self->{'_doc_id'},
					      $content);
    } else {
	return $self->{'_repository'}->content($filename,
					       $self->{'_doc_id'});
    }
}

# TODO:  Implement a 'dirty' flag to tell if doc has been changed

=head2 state([$state[, $comment]])

Gets or sets the state of the document.

=cut

sub state {
    my $self = shift;
    my $state = shift;
    my $comment = shift;

    if (! defined $state) {
	return $self->{_state};
    } elsif(! defined $self->{_STATES}->{$state}) {
	$self->_set_error("Invalid state '$state'\n");
	return undef;
    } else {
	$self->{_state} = $state;
	return $self->{_state};
    }
}

=head2 properties()

Returns a hash of general properties about the document

=cut

sub properties {
    my $self = shift;

    if (! $self->{'_metadata'}) {
	# This should probably be replaced by something more sophisticated,
	# however, this'll probably be reasonably efficient for now.
	foreach ($self->content('METADATA')) {
	    s/#.*//;
	    s/^\s+//;
	    s/\s+$//;
	    next unless length;
	    my ($var, $value) = split(/\s*=\s*/, $_, 2);
	    $self->{'_metadata'}->{$var} = $value;
	}
    }

    if (@_) {
	while (my ($key, $value) = each %{@_}) {
	    $self->{'_metadata'}->{$key} = $value;
	}
	return $self->_store_properties();
    } elsif (! $self->{'_metadata'}) {
	$self->{'_metadata'}->{title} = 'unknown';
	$self->{'_metadata'}->{state} = 'unknown';
	$self->{'_metadata'}->{size} = -1;
	$self->{'_metadata'}->{date} = '0000-00-00';
    }

    return $self->{'_metadata'};
}

# Helper routine to persist the current properties in memories
sub _store_properties {
    my $self = shift;

    my $content = '';
    foreach my $key (sort keys %{$self->{'_metadata'}}) {
	my $value = $self->{'_metadata'}->{$key};
	$content .= "$key = $value\n";
    }
    $self->content('METADATA', $content);

    return 1;
}

sub diff {
    my $self = shift;
    my $revA = shift;
    my $revB = shift;

    # TODO:  Implement a diff feature
    my $text = "unimplemented";
    return $text;
}

=head2 comment([$cid], [$comment])

Gets or sets the comment information for a given comment ID $cid,
or adds a new $comment if $cid is not defined, or returns all of
the comments if neither parameter is specified.

=cut

sub comment {
    my $self = shift;
    my $cid = shift;
    my $comment = shift;

    if (defined $cid) {
	# TODO:  Load the given comment
	if (defined $comment) {
	    # TODO:  Update the comment
	} else {
	    # TODO:  Return the comment
	}
    } else {
	if (defined $comment) {
	    # TODO:  Create a new comment
	} else {
	    # TODO:  Return array of all comments
	}
    }
}

=head2 keywords([@keywords])

Gets or sets the list of keywords for the document.

=cut

sub keywords {
    my $self = shift;
    my @keywords = @_;

    if (@keywords) {
	# TODO:  Set keywords
    } else {
	# TODO:  Return keywords
    }
}

=head2 watcher([$cid], [$comment])

Gets or sets the watcher information for a given watcher ID $wid,
or adds a new $watcher if $wid is not defined, or returns all of
the watchers if neither parameter is specified.

=cut

sub watcher {
    my $self = shift;
    my $wid = shift;
    my $watcher = shift;

    if (defined $wid) {
	# TODO:  Get the watcher info
	if (defined $watcher) {
	    # TODO:  Update the watcher info
	} else {
	    # TODO:  Return the watcher info for $wid
	}
    } else {
	if (defined $watcher) {
	    # TODO:  Create a new watcher
	} else {
	    # TODO:  Return array of all watchers for this document
	}
    }
}

1;
__END__

# TODO:  Docs

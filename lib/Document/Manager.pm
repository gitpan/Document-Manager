
# Think about ways to modularly add the above functionality or wrapper this
# instead of implementing it directly here.  E.g. metadata 'plug in' for 
# attributes instead of hardcoding the metadata here.

=head1 NAME

Document::Manager

=head1 SYNOPSIS

my $dms = new Document::Manager;

#TODO - add API

=head1 DESCRIPTION

This module provides a simple interface for managing a collection of
revision-controlled documents.  A document is a collection of one or
more files that are checked out, modified, and checked back in as a
unit.  Each revision of a document is numbered, and documents can be
reverted to older revisions if needed.  A document can also have an
arbitrary set of metadata associated with it.

=head1 FUNCTIONS

=cut

package Document::Manager;

use strict;

use vars qw($VERSION %FIELDS);
our $VERSION = '0.07';

use fields qw(
              _repository
              _error_msg
              );


=head2 new($confighash)

Creates a new document manager object.  

=cut

sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = bless [\%FIELDS], $class;

    while (my ($field, $value) = each %args) {
	$self->{"|$field"} = $value
	    if (exists $FIELDS{"_$field"});
    }

    # Specify defaults
    # TODO:  Better initialization for the repository
    $self->{_repository} = new Document::Repository;

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

=head2 checkout()

Checks out a copy of the document specified by $doc_id, placing
a copy into the directory specified by $dir.  By default it will
return the most recent revision, but a specific revision can be
retrieved by specifying $revision.

Returns the filename(s) copied into $dir on success.  If there is an
error, it returns undef.  The error message can be retrieved via
get_error().

=cut

sub checkout {
    my $self = shift;
    my $dir = shift;
    my $doc_id = shift;
    my $revision = shift;
    $self->_set_error('');

    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    if (! $dir || ! -d $dir) {
	$self->_set_error("Invalid dir specified to checkout()");
	return undef;
    }

    return $_repository->get($doc_id, $revision, $dir);
}

=head2 checkin()

Commits a new revision to the document.  Returns the document's new
revision number.

=cut

sub checkin {
    my $self = shift;
    my $doc_id = shift;
    my @files = @_;

    # Given a valid document id,
    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    my $new_revision = $_repository->put($doc_id, @files);

    # TODO log / trigger notifications
    return $new_revision;
}

=head2 query()

Returns a list of documents with property constraints meeting certain
conditions.  

# TODO
=cut

sub query {
    my $self = shift;
    # Pass in a function pointer we'll use for determine matching docs
    # Could we cache properties?  Store in a database?  Or is that higher level?
    # Return list of matching documents
}

=head2 revert()

Reverts the given document to a prior revision number

# TODO
=cut

sub revert {
    my $self = shift;
    my $doc_id = shift;
    my $new_revision = shift;

    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    my $current_revision = 42;
    if ($new_revision >= $current_revision) {
	# TODO:  Error - this revision number is too high
    }

    # get the old revision of the document
    # check it in as a new revision
    # log / trigger notifications
}

=head2 lock()

Locks a document for the given user for a specified period of time

=cut

sub lock {
    my $self = shift;
    my $doc_id = shift;

    # Given a valid document id
    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    # apply 'lock' on the document for the specified period by this uid
}

=head2 unlock() 

Unlocks a document, if it is locked

=cut

sub unlock {
    my $self = shift;
    my $doc_id = shift;

    # Given a valid document id
    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    # If the document has been locked by this user
    # unlock it
}

=head2 properties()

Gets or sets the properties for a given document id

=cut

sub properties {
    my $self = shift;

    # Given a valid document id
    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    # Retrieve the properties for this document
    my $properties = '';

    return $properties;
}

=head2 stats()

Returns a hash containing statistics about the document repository as a
whole, such as number of documents, disk space used, etc.

=cut

sub stats {
    my $self = shift;

    return $self->{_repository}->stats();
}


1;


=head1 NAME

Document::Repository

=head1 SYNOPSIS

my $repository = new Document::Repository;

my $doc_id = $repository->add($filename);

my $filename = $repository->get($doc_id, $dir);

$repository->put($doc_id, $filename, $filename, $filename)
    or die "couldn't put $filename";

$repository->delete($doc_id)
    or die "couldn't delete $doc_id";

=head1 DESCRIPTION

This module implements a repository of documents, providing general
access to add/get/delete documents.  This module is not intended to be
used directly; for that see Document::Manager.  This acts as a general
purpose backend.

A document is a collection of one or more files that are checked out,
modified, and checked back in as a unit.  Each revision of a document is
numbered, and documents can be reverted to older revisions if needed.  A
document can also have an arbitrary set of metadata associated with it.

=head1 FUNCTIONS

=cut

package Document::Repository;

use strict;
use File::Copy;
use File::Path;
use File::Spec::Functions qw(:ALL);


use vars qw(%FIELDS);

use fields qw(
              _repository_dir
              _repository_permissions
              _next_id
              _error_msg
	      _debug
              );


=head2 new($confighash)

Establishes the repository interface object.  You must pass it the
location of the repository, and optionally can indicate what permissions
to use (0600 is the default).

If the repository already exists, indicate where Document::Repository
should start its numbering (e.g., you may want to store this info
in a config file or something between invokations...)

=cut

sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = bless [\%FIELDS], $class;

    while (my ($field, $value) = each %args) {
	if (exists $FIELDS{"_$field"}) {
	    $self->{"_$field"} = $value;
	    if ($args{debug} && $args{debug}>3 && defined $value) {
		warn 'Setting Document::Archive::_'.$field." = $value\n";
	    }
	}
    }

    # Specify defaults
    $self->{_repository_dir} ||= '/var/dms';
    $self->{_repository_permissions} ||= '0700';
    $self->{_next_id} = 1;

    # Verify everything is sane...
    if (! -d $self->{_repository_dir} ) {
	die "Repository directory '" . $self->{_repository_dir} . "' does not exist\n";
    }
    if (! -x $self->{_repository_dir} ) {
	die "Repository directory '" . $self->{_repository_dir} . "' is not accessible\n";
    }

    # Determine what the next id is based on the maximum document id number
    foreach my $doc_id ($self->documents()) {
	last if (! defined $doc_id);
	$self->dbg("Found document id '$doc_id'\n", 4);

	if ($doc_id && $doc_id >= $self->{_next_id}) {
	    $self->{_next_id} = $doc_id + 1;
	}
    }

    if ($self->{_debug} > 4) {
	warn "Document::Archive settings:\n";
	warn "  debug                  = $self->{_debug}\n";
	warn "  repository_dir         = $self->{_repository_dir}\n";
	warn "  repository_permissions = $self->{_repository_permissions}\n";
	warn "  next_id                = $self->{_next_id}\n";
    }

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
    return $self->{_error_msg} || '';
}

sub dbg {
    my $self = shift;
    my $message = shift || return undef;
    my $thresh = shift || 1;

    warn $message if ($self->{_debug} >= $thresh);
}

=head2 repository_path($doc_id, $rev_number)

Returns a path to the location of the document within the repository
repository. 

=cut

sub repository_path {
    my $self = shift;
    my $doc_id = shift || return undef;
    my $rev_number = shift;
    $self->_set_error('');

    my $repo = $self->{_repository_dir};

    # Verify the repository exists
    if (! $repo) {
	$self->_set_error("Document repository dir is not defined");
	return undef;
    } elsif (! -d $repo) {
	$self->_set_error("Document repository '$repo' does not exist");
	return undef;
    } elsif (! -x $repo) {
	$self->_set_error("Document repository '$repo' cannot be accessed by this user");
	return undef;
    }

    # Millions subdir
    if ($doc_id > 999999) {
        $repo = catdir($repo,
		       sprintf("M%03d", int($doc_id/1000000)));
    }

    # Thousands subdir
    if ($doc_id > 999) {
        $repo = catdir($repo,
		       sprintf("k%03d", int($doc_id/1000)%1000));
    }

    # Ones subdir
    $repo = catdir($repo,
		   sprintf("%03d", $doc_id % 1000));

    if (-d $repo && ! -x $repo) {
	$self->_set_error("Document directory '$repo' exists but is inaccessible\n");
	return undef;
    }

    # Get the current revision number by looking for highest numbered
    # file or directory if the document already exists
    if (! $rev_number && -d $repo) {
	if (! opendir(DIR, $repo)) {
	    $self->_set_error("Could not open directory '$repo' ".
			      "to find the max revision number: $!");
	    return undef;
	}
	my @files = sort { $a <=> $b } grep { /^\d+$/ } readdir(DIR);
	$rev_number = shift @files;
	closedir(DIR);
    }
    $rev_number ||= 1;

    $repo = catdir($repo,
		   sprintf("%03d", $rev_number));

    return $repo;
}


=head2 add()

Adds a new document to the repository.  Establishes a new document
ID and returns it.

If you wish to simply register the document ID without actually
uploading a file, send a zero-byte temp file.

Specify a $revision if you want the document to start at a revision
number other than 0.

Returns undef on failure.  You can retrieve the error message by
calling get_error().

=cut

sub add {
    my $self = shift;
    my $filename = shift;
    my $revision = shift || 0;
    $self->_set_error('');

    if (! $filename || ! -e $filename) {
	$self->_set_error("Invalid filename specified to add()");
	return undef;
    }

    my $doc_id = $self->{_next_id};
    die "Could not get next document id\n" unless ($doc_id);

    my $repo = $self->repository_path($doc_id, $revision) or
	die "Could not get repository path for doc '$doc_id', rev '$revision': "
	. $self->get_error();

    $self->dbg("Creating path '$repo' as $self->{_repository_permissions}\n", 2);
    eval { mkpath([$repo], 0, oct($self->{_repository_permissions})) };
    if ($@) {
	$self->_set_error("Error adding '$filename' to repository:  $@");
	return undef;
    }

    # Install the file into the repository
    if (! copy($filename, catfile($repo, $filename)) ) {
	$self->_set_error("Error copying '$filename' to repository: $!");
	return undef;
    }

    $self->{_next_id}++;
    return $doc_id;
}

=head2 get()

Retrieves a copy of the document specified by $doc_id of the given
$revision (or the latest, if not specified), and places it at
$location (or the cwd if not specified).  

The document is copied using the routine specified by $copy_function.
This permits overloading the behavior in order to perform network
copying, tarball dist generation, etc.

If defined, $copy_function must be a reference to a function that
accepts two parameters: an array of filenames (with full path) to be
copied, and the $destination parameter that was passed to get().  The
caller is allowed to define $destination however desired - it can be a
filename, URI, hash reference, etc.

If $copy_function is not defined, the default behavior is simply to call
the File::Copy routine copy($fn, $destination) iteratively on each file
in the document, returning the number of files

Returns the return value from $copy_function, or undef if get()
encountered an error (such as bad parameters).  The error message can be
retrieved via get_error().

=cut

sub get {
    my $self = shift;
    my $doc_id = shift || '';
    my $revision = shift || '';
    my $destination = shift || '';
    my $copy_function = shift || '';
    my $select_function = shift;

    $self->_set_error('');

    if (! $doc_id || $doc_id !~ /^\d+/) {
	$self->_set_error("Invalid doc_id '$doc_id' specified to get()");
	return undef;
    }

    my $repo = $self->repository_path($doc_id, $revision);

    $self->dbg("Getting files from '$repo'\n", 2);

    if (! opendir(DIR, $repo)) {
	$self->_set_error("Could not open '$repo' to checkout file: $!");
	return undef;
    }

    my @files = ();
    while (defined(my $filename = readdir DIR)) {
	$self->dbg("Considering file '$filename'\n",3);
	if ($filename =~ /^\./ ) {
	    $self->dbg("Skipping '$filename' since it is a hidden file\n",4);
	    next;
	} elsif (! -f catfile($repo, $filename)) {
	    $self->dbg("Skipping '$filename' since it is not a valid file\n",4);
	    next;
	}	    

	if (defined $select_function) {
	    $self->dbg("Applying custom selection function\n", 4);
	    next unless (&$select_function(catfile($repo,$filename)));
	}
	$self->dbg("Selecting file '$filename' to get", 3);
	push @files, catfile($repo, $filename);
    }
    closedir(DIR);

    $self->dbg("Retrieving document files (@files)\n",2);

    if ($copy_function) {
	return &$copy_function(\@files, $destination);
    } else {
	foreach my $filename (@files) {
	    if (! copy($filename, $destination)) {
		$self->_set_error("Could not copy '$filename' for document '$doc_id': $!");
		return undef;
	    } 
	}
    }
    return 1;
}

# Recursively iterates through the document repository, running the
# given function '$func' against document ids it finds.
sub _iterate_doc_ids {
    my $self = shift;
    my $dir = shift;
    my $func = shift;
    my $prefix = shift || '';

    if (! opendir(DIR, $dir)) {
	$self->_set_error("Could not open directory '$dir': $!\n");
	return undef;
    }
    while (defined(my $subdir = readdir DIR)) {
	if ($subdir =~ /^\d+$/) {
	    # This is a document subdir, so we process
	    if (! &$func("$prefix$subdir")) {
		$self->_set_error("Error running function while iterating '$subdir'");
		return undef;
	    }
	} elsif ($subdir =~ /^[Mk](\d+)$/) {
	    # This is a thousands (k) or millions (M) dir, so it contains
	    # additional subdirs for documents within it.  We recurse into
	    # this directory and continue processing...
	    if (! _iterate_doc_ids($subdir, $func, $1)) {
		return undef;
	    }
	}
    }
    close(DIR);
    
    return 1;
}

=head2 documents()

Returns a list of document ids in the system.

Note that if you have a lot of documents, this list could be huge, but
it's assumed you know what you're doing in this case...

=cut

sub documents {
    my $self = shift;

    my $repo = $self->{_repository_dir};
    $self->dbg("Getting list of documents from '$repo'\n", 4);

    our @documents = ();

    sub get_doc_ids { 
	my $doc_id = shift;
	push @documents, $doc_id; 
    }
    if (! $self->_iterate_doc_ids($repo, \&get_doc_ids)) {
	# Error msg will already be set by _iterate_doc in this case
	return undef;
    }

    return @documents;
}

=head2 revisions()

Lists the revisions for the given document id

=cut

sub revisions {
    my $self = shift;
    my $doc_id = shift || return undef;

    my $repo = $self->repository_path($doc_id);

    # Given a valid document id
    return undef unless $repo;

    # Retrieve all of the valid revisions of this document
    my @revisions;
    if (!opendir(DIR, $repo)) {
	$self->_set_error("Could not open repository '$repo': $!");
	return undef;
    }
    @revisions = grep { -d && /^\d+$/ } readdir(DIR);
    closedir(DIR);

    return @revisions;
}

=head2 stats()

Returns a hash containing statistics about the document repository as a
whole, such as number of documents, disk space used, etc.

=cut

sub stats {
    my $self = shift;
    my %stats;

    my $repo = $self->{_repository_dir};

    # Number of documents
    my @doc_ids = $self->documents();
    $stats{num_documents} = scalar @doc_ids;

    # Num revisions
    $stats{num_revisions} = 0;
    foreach my $doc_id (@doc_ids) {
	$stats{num_revisions} += ($self->revisions($doc_id) || 0);
    }

    # Disk space used
    $stats{disk_space} = `du -s $repo`;

    # Number of files
    $stats{num_files} = `find $repo -type f | wc -l`;

    # Number of known users

    $stats{next_id} = $self->{_next_id};

    return \%stats;
}


1;

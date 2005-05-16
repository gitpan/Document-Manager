
=head1 NAME

Document::Manager - A web service for managing documents in a central
repository.

=head1 SYNOPSIS

my $dms = new Document::Manager;

$dms->checkout($dir, $doc_id, $revision);

$dms->add();
$dms->checkin();
$dms->query();
$dms->revert();
$dms->lock();
$dms->unlock();
$dms->properties();
$dms->stats();

print $dms->get_error();

=head1 DESCRIPTION

B<Document::Manager> provides a simple interface for managing a
collection of revision-controlled documents.  A document is a collection
of one or more files that are checked out, modified, and checked back in
as a unit.  Each revision of a document is numbered, and documents can
be reverted to older revisions if needed.  A document can also have an
arbitrary set of metadata associated with it.

=head1 FUNCTIONS

=cut

package Document::Manager;
@Document::Manager::ISA = qw(WebService::TicketAuth::DBI);

use strict;
use Config::Simple;
use WebService::TicketAuth::DBI;
use Document::Repository;
use Document::Object;
use MIME::Base64;
use File::stat;
use File::Spec::Functions;
use DBI;
use SVG::Metadata;

use vars qw($VERSION %FIELDS);
our $VERSION = '0.12';

my $config_file = "/etc/webservice_dms/dms.conf";

use base 'WebService::TicketAuth::DBI';
use fields qw(
	      repo_dir
              repository
              _error_msg
	      _debug
	      _dbh
              );


=head2 new()

Creates a new document manager object.  

=cut

sub new {
    my $class = shift;
    my Document::Manager $self = fields::new($class);

    # Load up configuration parameters from config file
    my %config;
    my $errormsg = '';
    if (! Config::Simple->import_from($config_file, \%config)) {
        $errormsg = "Could not load config file '$config_file': " .
            Config::Simple->error()."\n";
    }

    $self->SUPER::new(%config);

    if (defined $config{'repo_dir'}) {
	$self->{'repo_dir'} = $config{'repo_dir'};
    }

    $self->{repository} = new Document::Repository( repository_dir => $self->{'repo_dir'} );

    if (! $self->{repository}) {
	$self->_set_error("Could not connect to repository\n");
	warn "Error:  Could not establish connection to repository\n";
    }

    return $self;
}

sub _repo {
    my $self = shift;

    if (! defined $self->{repository}) {
	$self->{'repository'} = 
	    new Document::Repository( repository_dir => $self->{'repo_dir'} );
    }
    return $self->{'repository'};
}

# Internal routine for setting the error message
sub _set_error {
    my $self = shift;
    $self->{'_error_msg'} = shift;
}

=head2 get_error()

Retrieves the most recent error message

=cut

sub get_error {
    my $self = shift;
    return $self->{'_error_msg'};
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

    return $self->_repo()->get($doc_id, $revision, $dir);
}

=head2 add()

Takes a hash of filenames => content pairs, and inserts each into the
dms as a separate document.  

Returns the new ID number of the document added, or undef if failed.

=cut

sub add {
    my $self = shift;
    warn "In Document::Manager::add()\n";

    my (%files) = (@_);
    my @doc_ids;
    my $doc_id;
    my ($sec, $min, $hr, $day, $month, $year) = (gmtime)[0..5];
    my $now = sprintf("%04s-%02s-%02s %02s:%02s:%02s",
		      $year+1900, $month+1, $day, $hr, $min, $sec);
    foreach my $filename (keys %files) {
	my $content = $files{$filename};
	($filename) = (File::Spec->splitpath($filename))[2];
	my $local_filename = catfile('/tmp', $filename);
	my $decoded = decode_base64($content);
	if (! open(FILE, ">$local_filename") ) {
	    warn "Could not open file '$local_filename' for writing: $!\n";
	    next;
	}
	binmode(FILE);
	print FILE $decoded;
	if (! close(FILE) ) {
	    warn "Could not close file '$local_filename':  $!\n";
	}
	warn "File data stored\n";

	$doc_id = $self->_repo()->add($local_filename);
	if ($doc_id) {
	    push @doc_ids, $doc_id;
	} else {
	    $self->_set_error($self->_repo()->get_error());
	}

	# Generate metadata
	my %properties;
	# TODO:  Determine file type.  For now assume SVG
	my $format = 'svg';

	# Based on file type, extract metadata
	if ($format eq 'svg') {
	    my $svgmeta = new SVG::Metadata;
	    if (! $svgmeta->parse($local_filename) ) {
		$self->_set_error($svgmeta->errormsg());
		warn $svgmeta->errormsg()."\n";
	    }
	    $properties{title}         = $svgmeta->title();
	    $properties{author}        = $svgmeta->author();
	    $properties{creator}       = $svgmeta->creator();
	    $properties{creator_url}   = $svgmeta->creator_url();
	    $properties{owner}         = $svgmeta->owner();
	    $properties{owner_url}     = $svgmeta->owner_url();
	    $properties{publisher}     = $svgmeta->publisher();
	    $properties{publisher_url} = $svgmeta->publisher_url();
	    $properties{license}       = $svgmeta->license();
	    $properties{license_date}  = $svgmeta->license_date();
	    $properties{description}   = $svgmeta->description();
	    $properties{language}      = $svgmeta->language();
	    $properties{keywords}      = $svgmeta->keywords();
	}

	$properties{title} ||= $filename;

	my $inode = stat($local_filename);

	$properties{state} = 'new';
	$properties{size}  = $inode->size;
	$properties{date}  = $now;
	$properties{mimetype} = `file -bi $local_filename`;  # TODO:  PApp::MimeType?
	chomp $properties{mimetype};

	if (! $self->properties($doc_id, %properties) ) {
	    warn "Error:  ".$self->get_error()."\n";
	}

	# Remove the temporary file
	warn "Unlinking temporary file\n";
	unlink($local_filename);
    }

    warn "Returning doc_id = '$doc_id'\n";
    return $doc_id;
}

=head2 checkin()

Commits a new revision to the document.  Returns the document's new
revision number, or undef if failed.

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

    my $new_revision = $self->_repo()->put($doc_id, @files);

    # TODO log / trigger notifications
    return $new_revision;
}

=head2 query()

Returns a list of documents with property constraints meeting certain
conditions.  

=cut

sub query {
    my $self = shift;

    warn "Calling query()\n";

    # Pass in a function pointer we'll use for determine matching docs
    # Could we cache properties?  Store in a database?  Or is that higher level?
    # Return list of matching documents

    my @objs = $self->_repo()->documents();
    return \@objs;
}

=head2 revert()

Reverts the given document to a prior revision number

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
	$self->_set_error("The specified new revision number '"
			  .$new_revision."' is higher than the "
			  ."current revision number '$current_revision'");
	return undef;
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

Gets or updates the properties for a given document id

=cut

sub properties {
    my $self = shift;
    my $doc_id = shift;

    # Given a valid document id
    if (! $doc_id || ($doc_id !~ /^\d+/)) {
	$self->_set_error("Invalid doc_id specified to properties()");
	print "Document id '$doc_id' provided to properties()\n";
	return undef;
    }

    # Retrieve the properties for this document
    my $doc = new Document::Object(repository => $self->_repo(),
				   doc_id     => $doc_id);

    return $doc->properties(@_);
}

=head2 stats()

Returns a hash containing statistics about the document repository as a
whole, including the following:

* Stats from Document::Repository::stats()
* Number of pending documents
* Number of documents new today
* Number of authors

=cut

sub stats {
    my $self = shift;

    my $stats = $self->_repo()->stats();

    $stats->{num_pending_docs}   = 0;  # TODO
    $stats->{num_new_today_docs} = 0;  # TODO
    $stats->{num_authors}        = 0;  # TODO

    return $stats;
}

=head2 state(doc_id[, state[, comment]])

Gets or sets the state of document in the system.  Returns undef if the 
specified doc_id does not exist, or does not have a valid state set.

=cut

sub state {
    my $self = shift;
    my $doc_id = shift;
    my $state = shift;
    my $comment = shift;

    if (! $doc_id) {
	$self->_set_error("No doc_id specified to Document::Manager::state\n");
	return undef;
    }

    my $doc = new Document::Object(repository => $self->_repo(),
				   doc_id     => $doc_id);
    $state = $doc->state($state);
    if (! $state) {
	$self->_set_error($doc->get_error());
	return undef;
    }

    if (defined $comment) {
	$doc->log($comment);
    }

    return $state;
}

# TODO:  Applies a converter/translator/test to a document

sub apply {
    my $self = shift;
    return 'Unimplemented';
}

# TODO:  Renders a set of docs based on a hierarchy scheme
sub render {
    my $self = shift;
    return 'Unimplemented';
}

# TODO:  Aggregates several separate documents into a single one (e.g., newsletter)
sub aggregate {
    my $self = shift;
    return 'Unimplemented';
}

# TODO:  Derives a new document from an existing document (e.g. from a template)
sub branch {
    my $self = shift;
    return 'Unimplemented';
    # Return new document
}

# TODO:  Links to another dms system
sub subscribe {
    my $self = shift;
    return 'Unimplemented';
}

sub metrics_pending_docs {
    my $self = shift;
    return 'Unimplemented';
}

sub metrics_new_docs_today {
    my $self = shift;
    return 'Unimplemented';
}

sub metrics_new_docs_this_month {
    my $self = shift;
    return 'Unimplemented';
}

sub metrics_authors {
    my $self = shift;
    return 'Unimplemented';
}

sub keyword_add {
    my $self = shift;
    my $doc_id = shift;
    my @keywords = @_;

    if (! defined $doc_id) {
	$self->_set_error("No doc_id specified to Document::Manager::keyword_add\n");
	return undef;
    }

    if (@keywords < 1) {
	$self->_set_error("No keywords specified to Document::Manager::keyword_add\n");
	return undef;
    }

    my $doc = new Document::Object(repository => $self->_repo(),
				   doc_id     => $doc_id);

    # TODO:  Maybe move keyword management into Document::Object ?
    # Ensure we have the unique union of keywords
    my %kwds;
    foreach my $k (@keywords, split(/;/, $doc->properties('keyword'))) {
	$k =~ s/;/,/g;
	$kwds{lc($k)} = 1;
    }
    my $retval = $doc->properties('keyword', join(';', sort keys %kwds));

    $doc->log("Added keywords: @keywords\n");

    return $retval;
}

# Removes one or more keywords if they exist
sub keyword_remove {
    my $self = shift;
    my $doc_id = shift;
    my @keywords = @_;

    my $doc = new Document::Object(repository => $self->_repo(),
				   doc_id     => $doc_id);

    my %kwds;
    foreach my $k (split(/;/, $doc->properties('keyword'))) {
	$kwds{$k} = 1;
    }
    foreach my $k (@keywords) {
	$k =~ s/;/,/g;
	delete $kwds{lc($k)};
    }
    my $retval = $doc->properties('keyword', join(';', sort keys %kwds));

    $doc->log("Removed keywords:  @keywords\n");
    return $retval;
}

# Determines if function has valid extension and/or mimetype
sub validate_document_type {
    my $self = shift;
    return 'Unimplemented';
}

sub validate_properties {
    my $self = shift;
    return 'Unimplemented';
}

sub make_thumbnail {
    my $self = shift;
    return 'Unimplemented';
}

# Reporting issues/bugs about a document
sub issue {
    my $self = shift;
    return 'Unimplemented';
}

sub comment {
    my $self = shift;
    return 'Unimplemented';
}

sub create_dist {
    my $self = shift;
    return 'Unimplemented';
}

1;

package LXRng::Index::DBI;

use strict;
use DBI;

use base qw(LXRng::Index::Generic);

sub transaction {
    my ($self, $code) =  @_;
    if ($self->dbh->{AutoCommit}) {
	$self->dbh->{AutoCommit} = 0;
	$code->();
	$self->dbh->{AutoCommit} = 1;
    }
    else {
	# If we're in a transaction already, don't return to
	# AutoCommit state.
	$code->();
    }
    $self->dbh->commit();
}

sub _to_task {
    my ($self, $rfile_id, $task) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_to_task_ins'} ||=
	$dbh->prepare(qq{insert into ${pre}filestatus(id_rfile)
			     select ? where not exists
			     (select 1 from ${pre}filestatus 
			      where id_rfile = ?)});
    $sth->execute($rfile_id, $rfile_id);

    $sth = $$self{'sth'}{'_to_task_upd'}{$task} ||=
	$dbh->prepare(qq{update ${pre}filestatus set $task = 't' 
			     where $task = 'f' and id_rfile = ?});
    return $sth->execute($rfile_id) > 0;
}


sub to_index {
    my ($self, $rfile_id) = @_;

    return $self->_to_task($rfile_id, 'indexed');
}

sub to_reference {
    my ($self, $rfile_id) = @_;

    return $self->_to_task($rfile_id, 'referenced');
}

sub to_hash {
    my ($self, $rfile_id) = @_;

    return $self->_to_task($rfile_id, 'hashed');
}

sub _get_tree {
    my ($self, $tree) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_tree'} ||=
	$dbh->prepare(qq{select id from ${pre}trees where name = ?});
    my $id;
    if ($sth->execute($tree) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_release {
    my ($self, $tree_id, $release) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_release'} ||=
	$dbh->prepare(qq{select id from ${pre}releases
			     where id_tree = ? and release_tag = ?});
    my $id;
    if ($sth->execute($tree_id, $release) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_file {
    my ($self, $path) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_file'} ||=
	$dbh->prepare(qq{select id from ${pre}files where path = ?});
    my $id;
    if ($sth->execute($path) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_rfile_by_release {
    my ($self, $rel_id, $path) = @_;
    
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_rfile_by_release'} ||=
	$dbh->prepare(qq{select r.id
			     from ${pre}filereleases fr, ${pre}files f,
			     ${pre}revisions r
			     where fr.id_rfile = r.id and r.id_file = f.id
			     and fr.id_release = ? and f.path = ?});

    my $id;
    if ($sth->execute($rel_id, $path) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_symbol {
    my ($self, $symbol) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_symbol'} ||=
	$dbh->prepare(qq{select id from ${pre}symbols where name = ?});
    my $id;
    if ($sth->execute($symbol) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}


sub _add_include {
    my ($self, $file_id, $inc_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_include'} ||=
	$dbh->prepare(qq{insert into ${pre}includes(id_rfile, id_include_path)
			     values (?, ?)});
    my $id;
    $sth->execute($file_id, $inc_id);

    return 1;
}

sub _includes_by_id {
    my ($self, $file_id) = @_;

}

sub _symbol_by_id {
    my ($self, $id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_symbol_by_id'} ||=
	$dbh->prepare(qq{select * from ${pre}symbols
			     where id = ?});
    my @res;
    if ($sth->execute($id) > 0) {
	@res = $sth->fetchrow_array();
    }
    $sth->finish();

    return @res;
}

sub _identifiers_by_name {
    my ($self, $rel_id, $symbol) = @_;

    my $sym_id = $self->_get_symbol($symbol);
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_identifiers_by_name'} ||=
	$dbh->prepare(qq{
	    select i.id, i.type, f.path, i.line, s.name, c.type, c.id, 
	    i.id_rfile
		from ${pre}identifiers i
	        left outer join ${pre}identifiers c on i.context = c.id
		left outer join ${pre}symbols s on c.id_symbol = s.id,
		${pre}files f, ${pre}filereleases r, ${pre}revisions v
		where i.id_rfile = v.id and v.id = r.id_rfile 
		and r.id_release = ? and v.id_file = f.id 
		and i.id_symbol = ?});

    $sth->execute($rel_id, $sym_id);
    my $res = $sth->fetchall_arrayref();

    use Data::Dumper;
    foreach my $def (@$res) {
#	warn Dumper($def);
	$$def[7] = 42;
#	my @files = $self->get_referring_files($rel_id, $$def[7]);
#	warn Dumper(\@files);
    }

    return $res;
}

sub _symbols_by_file {
    my ($self, $rfile_id) = @_;
    
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_symbols_by_file'} ||=
	$dbh->prepare(qq{select distinct s.name 
			     from ${pre}usage u, ${pre}symbols s
			     where id_rfile = ? and u.id_symbol = s.id});
    $sth->execute($rfile_id);
    my %res;
    while (my ($symname) = $sth->fetchrow_array()) {
	$res{$symname} = 1;
    }

    return \%res;
}

sub _add_usage {
    my ($self, $file_id, $line, $symbol_id) = @_;
    
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_usage'} ||=
	$dbh->prepare(qq{insert into ${pre}usage(id_rfile, line, id_symbol)
			     values (?, ?, ?)});
    $sth->execute($file_id, $line, $symbol_id);

    return 1;
}

sub _usage_by_file {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_usage_by_file'} ||=
	$dbh->prepare(qq{select s.name, u.line
			     from ${pre}usage u, ${pre}symbols s
			     where id_rfile = ? and u.id_symbol = s.id});
    $sth->execute($rfile_id);

    die "Unimplemented";
}

sub _rfile_path_by_id {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_rfile_path_by_id'} ||=
	$dbh->prepare(qq{select f.path from ${pre}files f, ${pre}revisions r
			     where f.id = r.id_file and r.id = ?});
    my $path;
    if ($sth->execute($rfile_id) > 0) {
	($path) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $path;
}

sub _get_includes_by_file {
    my ($self, $res, $rel_id, @rfile_ids) = @_;

    my $placeholders = join(', ', ('?') x @rfile_ids);
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $dbh->prepare(qq{select rf.id, f.path 
				   from ${pre}revisions rf,
				   ${pre}filereleases v,
				   ${pre}includes i,
				   ${pre}revisions ri,
				   ${pre}files f
				   where rf.id = i.id_rfile
				   and rf.id_file = f.id
				   and rf.id = v.id_rfile
				   and v.id_release = ?
				   and i.id_include_path = ri.id_file
				   and ri.id in ($placeholders)});


    $sth->execute($rel_id, @rfile_ids);
    my $files = $sth->fetchall_arrayref();
    $sth->finish();

    my @recurse;
    foreach my $r (@$files) {
	push(@recurse, $$r[0]) unless exists($$res{$$r[0]});

	$$res{$$r[0]} = $$r[1];
    }

    $self->_get_includes_by_file($res, $rel_id, @recurse) if @recurse;

    return 1;
}

sub add_hashed_document {
    my ($self, $rfile_id, $doc_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'add_hashed_document'} ||=
	$dbh->prepare(qq{insert into ${pre}hashed_documents(id_rfile, doc_id)
			     values (?, ?)});
    $sth->execute($rfile_id, $doc_id);

    return 1;
}

sub get_hashed_document {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_hashed_document'} ||=
	$dbh->prepare(qq{select doc_id from ${pre}hashed_documents
			     where id_rfile = ?});
    my $doc_id;
    if ($sth->execute($rfile_id) > 0) {
	($doc_id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $doc_id;
}

sub get_symbol_usage {
    my ($self, $rel_id, $symid) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_symbol_usage'} ||=
	$dbh->prepare(qq{
	    select u.id_rfile, u.line
		from ${pre}usage u, ${pre}filereleases fr
		where u.id_symbol = ? 
		and u.id_rfile = fr.id_rfile and fr.id_release = ?});

    $sth->execute($symid, $rel_id);
    my $res = $sth->fetchall_arrayref();
    $sth->finish();

    return $res;
}

sub get_identifier_info {
    my ($self, $ident, $rel_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_identifier_info'} ||=
	$dbh->prepare(qq{
	    select s.name, s.id,
	    i.id, i.type, f.path, i.line, cs.name, c.type, c.id,
	    i.id_rfile
		from ${pre}identifiers i
	        left outer join ${pre}identifiers c on i.context = c.id
		left outer join ${pre}symbols cs on c.id_symbol = cs.id,
		${pre}symbols s, ${pre}revisions r, ${pre}files f
		where i.id = ? and i.id_symbol = s.id 
		and i.id_rfile = r.id and r.id_file = f.id});

#	    select i.id_rfile, f.path, i.line, i.type, i.context, s.id, s.name
#		from identifiers i, symbols s, revisions r, files f
#		where i.id = ? and i.id_symbol = s.id 
#		and i.id_rfile = r.id and r.id_file = f.id});

    unless ($sth->execute($ident) == 1) {
	return undef;
    }

    my ($symname, $symid,
	$iid, $type, $path, $line, $cname, $ctype, $cid, $rfile_id) =
	    $sth->fetchrow_array();
    $sth->finish();

    my $refs = {$rfile_id => $path};
    $self->get_referring_files($rel_id, $rfile_id, $refs);
    my $usage = $self->get_symbol_usage($rel_id, $symid);

    my %reflines;
    foreach my $u (@$usage) {
	next unless $$refs{$$u[0]};
	$reflines{$$refs{$$u[0]}} ||= [];
	push(@{$reflines{$$refs{$$u[0]}}}, $$u[1]);
    }

    return ($symname, $symid, 
	    [$iid, $type, $path, $line, $cname, $ctype, $cid, $rfile_id],
	    \%reflines);
}

sub get_rfile_timestamp {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_rfile_timestamp'} ||=
	$dbh->prepare(qq{
	    select extract(epoch from last_modified_gmt)::integer,
	    last_modified_tz
		from ${pre}revisions where id = ?});
    
    unless ($sth->execute($rfile_id) == 1) {
	return undef;
    }

    my ($epoch, $tz) = $sth->fetchrow_array();
    $sth->finish();

    return ($epoch, $tz);
}    

1;

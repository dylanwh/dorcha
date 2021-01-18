package Dorcha::Build;
use Mojo::Base -base, -signatures;

use overload '""' => 'to_string', fallback => 1;

use Mojo::Util qw(trim sha1_sum unindent);
use Mojo::File qw(path tempdir);
use Mojo::JSON qw(j);
use Mojo::Loader qw(data_section);

has 'name';
has 'digest'     => sub ($self) { sha1_sum(j([$self->directives, $self->files])) };
has 'directives' => sub { [] };
has 'files'      => sub { [] };
has 'package'    => sub {'main'};
has 'source_dir' => sub { path('.')->to_abs };
has 'build_dir'  => sub ($self) { $self->source_dir->child(".dorcha_cache", $self->short_digest . ".build_dir")->to_abs->make_path };
has 'iidfile'    => sub ($self) { $self->build_dir->child('IMAGE_ID') };
has 'tagfile'    => sub ($self) { $self->build_dir->child('TAG') };
has 'image_id'   => sub ($self) { $self->iidfile->slurp };
has 'tag';

sub short_digest($self) {
  return substr($self->digest, 0, 7);
}

sub publish($self) {
  my $published = $self->build_dir->child('published');

  return if not $self->tag;
  return if -f $published;
  my $rv = system('docker', 'push', $self->deref_tag);
  die "publish failed" if $rv != 0;

  $published->touch;

  return 1;
}

sub deref_tag($self) {
  if ($self->tag && ref $self->tag) {
    local $_ = $self;
    return $self->tag->($self);
  }
  else {
    return $self->tag;
  }
}

sub build ($self) {
  my $build_dir = $self->build_dir;
  my $iidfile   = $self->iidfile;

  if ($self->name) {
    my $link = $self->source_dir->child($self->name);
    if (-l $link) {
      $link->remove;
    }
    symlink $build_dir, $link;
  }

  if (-f $iidfile) {
    printf "already built %s (tag: %s, id: %s)\n", $self->short_digest,
      $self->deref_tag // '(none)', $self->image_id;
    return;
  }

  my $dockerfile = join("\n", $self->directives->@*);
  $build_dir->child('Dockerfile')->spurt($dockerfile);
  foreach my $file ($self->files->@*) {
    my $path = $build_dir->child($file->{name});
    $path->spurt($file->{content});
    if ($file->{mode}) {
      $path->chmod($file->{mode});
    }
  }

  my @args = ('--iidfile' => $iidfile);
  if ($self->tag) {
    push @args, '-t' => $self->deref_tag;
  }

  my $rv = system('docker', 'build', @args, $build_dir);
  if ($rv != 0) {
    $iidfile->remove;
    die "build failed";
  }

  if ($self->tag) {
    $self->tagfile->spurt($self->deref_tag);
  }

}

sub to_string($self, @args) {
  if (-f $self->tagfile) {
    $self->tagfile->slurp;
  }
  else {
    $self->image_id;
  }
}

sub _emit ($self, $directive) {
  delete $self->{digest};
  delete $self->{build_dir};
  push @{$self->directives}, $directive;
}

sub _emit_file ($self, $file) {
  push @{$self->files}, $file;
}

sub include ($self, $other) {
  delete $self->{digest};
  delete $self->{build_dir};
  push $self->directives->@*, $other->directives->@*;
  push $self->files->@*, $other->files->@*;
}

sub from ($self, $image, $as = undef) {
  $self->_emit(sprintf "FROM %s%s", $image, $as ? " AS $as" : "");
}

sub volume ($self, $volume) {
  $self->_emit("VOLUME $volume");
}

sub env ($self, $name, $value) {
  if ($self->directives->[-1] =~ /^ENV /) {
    my $dir = pop $self->directives->@*;
    $self->_emit("$dir $name=$value");
  }
  else {
    $self->_emit("ENV $name=$value");
  }
}

sub user ($self, $user) {
  $self->_emit("USER $user");
}

sub workdir ($self, $workdir) {
  $self->_emit("WORKDIR $workdir");
}

sub shell ($self, $script) {
  $self->_emit("RUN " . j([ 'sh', '-c', "set -eu\n" . unindent(trim($script))]));
}

sub run ($self, $cmd) {
  $self->_emit("RUN " . _cmd($cmd));
}

sub cmd ($self, $cmd) {
  $self->_emit("CMD " . _cmd($cmd));
}

sub entrypoint ($self, $cmd) {
  $self->_emit("ENTRYPOINT " . _cmd($cmd));
}

sub copy ($self, @args) {
  my $options = ref($args[0]) eq 'HASH' ? shift @args : {};
  my ($src, $dst) = @args;
  unless ($options->{from}) {
    my $content = data_section($self->package, $src)
      or die "missing data section $src in package " . $self->package;
    $self->_emit_file({
      mode => delete $options->{chmod}, name => $src, content => $content,
    });
  }
  my @cmd = ('COPY');
  foreach my $option (keys %$options) {
    push @cmd, "--$option=$options->{$option}";
  }
  push @cmd, $src, $dst;
  $self->_emit("@cmd");
}


sub _cmd($cmd) {
  if (ref $cmd eq 'ARRAY') {
    return j($cmd);
  }
  else {
    return trim($cmd);
  }
}

1;

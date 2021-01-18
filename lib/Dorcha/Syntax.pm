package Dorcha::Syntax;
use Mojo::Base -strict;
use Mojo::File qw(path);
use base 'Exporter';

use Dorcha::Build;

our $BUILD;
our @EXPORT = qw( build include from volume env user workdir shell run cmd entrypoint copy tag name);

sub build (&) {
  my ($code) = @_;
  my ($package, $file, $line) = caller;
  my $source_file = path($file)->to_abs;
  my $source_dir = $source_file->dirname;
  my $build = Dorcha::Build->new(package => $package, source_dir => $source_dir);
  local $BUILD = $build;

  eval {
    $code->();
    $build->build;
  };
  if (my $error = $@) {
    warn "build_dir: ", $build->build_dir->to_abs, "\n", "digest: ", $build->digest, "\n",
      "tag: ", $build->deref_tag // "(no tag)", "\n";
    die $error;
  }
  if ($build->tag) {
    $build->publish;
  }

  return $build;
}

sub include($) {
  $BUILD->include(@_);
}

sub from ($;$) {
  $BUILD->from(@_);
}

sub name ($) {
  $BUILD->name(@_);
}

sub tag (&) {
  $BUILD->tag(@_);
}

sub volume ($) {
  $BUILD->volume(@_);
}

sub env($$) {
  $BUILD->env(@_);
}

sub user($) {
  $BUILD->user(@_);
}

sub workdir($) {
  $BUILD->workdir(@_);
}

sub shell ($) {
  $BUILD->shell(@_);
}

sub run($) {
  $BUILD->run(@_);
}

sub cmd($) {
  $BUILD->cmd(@_);
}

sub entrypoint($) {
  $BUILD->entrypoint(@_);
}

sub copy(@) {
  $BUILD->copy(@_);
}

1;

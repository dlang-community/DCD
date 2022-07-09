 project('dsymbol', 'd',
    meson_version: '>=0.44',
    license: 'BSL-1.0',
    version: '0.4.8'
)

project_soversion = '0'

pkgc = import('pkgconfig')
dparse_dep = dependency('dparse', version: '>= 0.9.0', fallback: ['dparse', 'dparse_dep'])
dcontainers_dep = dependency('dcontainers', version: '>= 0.8.0', fallback: ['dcontainers', 'dcontainers_dep'])

#
# Sources
#
dsymbol_src = [
    'src/dsymbol/builtin/names.d',
    'src/dsymbol/builtin/symbols.d',
    'src/dsymbol/cache_entry.d',
    'src/dsymbol/conversion/first.d',
    'src/dsymbol/conversion/package.d',
    'src/dsymbol/conversion/second.d',
    'src/dsymbol/deferred.d',
    'src/dsymbol/import_.d',
    'src/dsymbol/modulecache.d',
    'src/dsymbol/scope_.d',
    'src/dsymbol/semantic.d',
    'src/dsymbol/string_interning.d',
    'src/dsymbol/symbol.d',
    'src/dsymbol/tests.d',
    'src/dsymbol/type_lookup.d',
]

src_dir = include_directories('src/')

#
# Targets
#
dsymbol_lib = library('dsymbol',
        [dsymbol_src],
        include_directories: [src_dir],
        install: true,
        version: meson.project_version(),
        soversion: project_soversion,
        dependencies: [dparse_dep, dcontainers_dep]
)

pkgc.generate(name: 'dsymbol',
              libraries: [dsymbol_lib],
              subdirs: 'd/dsymbol',
              requires: ['dparse', 'dcontainers'],
              version: meson.project_version(),
              description: 'Library for lexing and parsing D source code.'
)

# for use by others which embed this as subproject
dsymbol_dep = declare_dependency(
    link_with: [dsymbol_lib],
    include_directories: [src_dir],
    dependencies: [dparse_dep, dcontainers_dep]
)

#
# Tests
#
if meson.get_compiler('d').get_id() == 'llvm'
  extra_args = ['-main', '-link-defaultlib-shared']
else
  extra_args = ['-main']
endif

dsymbol_test_exe = executable('test_dsymbol',
    [dsymbol_src],
    include_directories: [src_dir],
    dependencies: [dparse_dep, dcontainers_dep],
    d_unittest: true,
    link_args: extra_args
)
test('test_dsymbol', dsymbol_test_exe)

#
# Install
#
install_subdir('src/dsymbol/', install_dir: 'include/d/dsymbol/')

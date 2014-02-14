function [ S, itypes ] = cvx_create_structure( varargin )

%CVX_CREATE_STRUCTURE Construct a basis for a structured matrix.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Parse the arguments, if needed %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

S = [];
itypes = {};
if iscell( varargin{1} ),
    orig = varargin{1};
    name = varargin{2};
    args = varargin{3};
    nargs = numel( orig );
else
    nargs = nargin;
    orig = varargin;
    name = orig;
    args = cell( 1, nargs );
    if ischar( varargin{1} ),
        amin = 1;
    else
        args{1} = varargin{1};
        name{1} = '';
        varargin{1} = '';
        amin = 2;
    end
    toks = regexp( varargin, '^([a-zA-Z]\w*)(\(.*\))?$', 'tokens' );
    for k = amin : nargs,
        tok = toks{k};
        if isempty( tok ),
            if k == 1, type = 'Variable'; else type = 'Structure'; end
            error( sprintf('CVX:Invalid%sSpec',type), 'Invalid %s specification: %s', lower(type), varargin{k} );
        end
        tok = tok{1};
        name{k} = tok{1};
        if length(tok) > 1 && ~isempty( tok{2} ),
            try
                args{k} = evalin( 'caller', [ '{', tok{2}(2:end-1), '};' ] );
            catch exc
                error( exc.identifier, exc.message );
            end
        else
            args{k} = {};
        end
    end
end
if nargs == 1 && nargout > 0,
    return
end
sz = args{1};
if iscell( sz ),
    sz = [ sz{:} ];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Scan the structure strings for symmetry and complex cases. We now handle %
% these cases specially for improved performance.                          %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

uplo = '';
do_semi = 0;
do_skew = false;
do_conj = false;
do_comp = false;
do_symm = false;
is_toep = false;
is_hank = false;
sflags  = false(1,nargs);
bflags  = false(1,nargs);
pflags  = false(1,nargs);
for k = 2 : nargs,
    amin = 0; amax = 0;
    nm = lower( name{k} );
    if ~isempty(uplo),
        switch nm,
            case { 'bidiagonal', 'triangular', 'hessenberg' },
                pflags(k) = true;
                bflags(k) = true;
                sflags(k) = true;
                name{k} = [ uplo, '_', nm ];
            otherwise,
                error( 'CVX:InvalidStructure', 'Invalid structure type: %s %s', orig{k-1}, orig{k} );
        end
        uplo = '';
        continue;
    else
        switch nm,
            case 'complex',        
                                  do_comp = true;
                if do_semi, do_conj = true; end
            case 'symmetric',
                sflags(k) = true;                 do_symm = true;
            case 'symmetric_ut',
                sflags(k) = true;
                pflags(k) = true;
            case 'hermitian',      
                sflags(k) = true; do_comp = true; do_symm = true; do_conj = true;
            case 'skew_symmetric', 
                sflags(k) = true;                 do_symm = true;                 do_skew = true;
            case 'skew_hermitian', 
                sflags(k) = true; do_comp = true; do_symm = true; do_conj = true; do_skew = true;
            case {'hankel','upper_hankel'},
                pflags(k) = true;
                sflags(k) = true;
                is_hank = true;
            case 'toeplitz', 
                pflags(k) = true;
                is_toep = true;
            case 'semidefinite',
                do_semi = k; do_symm = true;
                if do_comp, do_conj = true; end
            case { 'upper', 'lower' },
                uplo = nm;
            case {'upper_bidiagonal','upper_triangular','upper_hessenberg',...
                  'lower_bidiagonal','lower_triangular','lower_hessenberg' }, ...
                pflags(k) = true;
                bflags(k) = true;
                sflags(k) = true;
            case { 'diagonal', 'tridiagonal' },
                pflags(k) = true;
                bflags(k) = true;
            case 'scaled_identity',
                pflags(k) = true;
                bflags(k) = true;
                is_toep = true;
            case 'banded',
                amin = 1; amax = 2;
                pflags(k) = true;
                sflags(k) = length(args{k}) == 2 && ~isequal(args{k}{1},args{k}{2});
                bflags(k) = true;
            case { 'binary', 'integer', 'nonnegative', 'semidefinite', 'epigraph_', 'hypograph_', 'geometric_', 'linear_' },
                itypes{end+1} = nm; %#ok
            otherwise,
                pflags(k) = true;
                if ~exist( [ 'cvx_s_', nm ], 'file' ),
                    error( 'CVX:UnknownStructure', 'Undefined matrix structure type: %s\nTrying to declare multiple variables? Use the VARIABLES keyword instead.', orig{k} );
                end
        end
    end
    if length( args{k} ) < amin,
        error( 'CVX:InvalidStructure', 'Not enough arguments: %s', orig{k} );
    elseif length( args{k} ) > amax,
        error( 'CVX:InvalidStructure', 'Too many arguments: %s', orig{k} );
    end
end
if ~isempty(uplo),
    error( 'CVX:InvalidStructure', 'Invalid structure type: %s', orig{end} );
end    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Quick exit for no structure %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if numel( itypes ) == nargs - 1 && nargout > 0,
    return
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Verify symmetry consistency %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if nnz(sflags) > 1 || do_semi && ( do_skew || do_comp && ~do_conj ) || is_toep && is_hank,
    if do_semi, sflags(do_semi) = true; end
    error( 'CVX:InvalidStructure', 'These forms of structure may not be specified simultaneously:\n   %s', sprintf(' %s', orig{sflags} ) );
elseif nnz(bflags) > 1,
    error( 'CVX:InvalidStructure', 'These forms of structure may not be specified simultaneously:\n   %s', sprintf(' %s', orig{bflags} ) );
elseif do_symm && sz(1) ~= sz(2),
    if do_semi, sflags(do_semi) = true; end
    error( 'CVX:InvalidStructure', 'This type of structure requires square matrices:%s', sprintf(' %s', orig{sflags} ) );
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Construct the basis matrices for the remaining structure elements        %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

strs = {};
for k = 2 : nargs,
    if pflags(k),
        try
            [ strs{end+1}, do_symm ] = feval( [ 'cvx_s_', lower(name{k}) ], sz( 1 ), sz( 2 ), do_symm, args{k}{:} ); %#ok
        catch exc
            error( exc.identifier, sprintf( 'Error constructing structure: %s\n   %s', orig{k}, exc.message ) );
        end
    end
end
if do_symm,
    [ strs{end+1}, do_symm ] = cvx_s_symmetric( sz(1), sz(2), do_symm ); %#ok
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% If multiple structures have been requested (e.g., toeplitz and banded),  %
% combine them together by finding bases for their orthogonal complements, %
% concatenating, and taking the orthogonal complement of that. This should %
% be used much less frequently than before---if ever---now that we handle  %
% symmetry as a special case for improved performance.                     %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
switch length( strs ),
    case 0,
        sz(end+1:2) = 1;
        nel = sz( 1 ) * sz( 2 );
        S = sparse( 1 : nel, 1 : nel, 1, nel, nel );
    case 1,
        S = strs{ 1 };
    otherwise,
        for k = 1 : length(strs),
            strs{k} = cvx_orthog_structure( strs{k} ); %#ok
        end
        S = cvx_orthog_structure( vertcat(strs{:}), true );
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Handle complex, skew-symmetric, and Hermitian structures.                %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if do_comp,
    S = [ S ; +1j * S ];
    S = S([1:end/2;end/2+1:end],:);
end
if do_skew || do_conj,
    r = (0:sz(1)-1)'; r = r(:,ones(1,sz(2)));
    c = 0:sz(2)-1; c = c(ones(1,sz(1)),:);
    ut = r < c; dg = r == c;
    if do_skew,
        S(:,ut) = - S(:,ut);
        S(:,dg) = 0;
    end
    if do_conj,
        S(:,ut) = conj(S(:,ut));
        S(:,dg) = real(S(:,dg));
    end
    S = S(any(S,2),:);
end
if do_semi,
    itypes{end+1} = 'semidefinite';
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Report an error of the structure is empty                                %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if isempty( S ),
    error( 'CVX:InvalidStructure', 'Incompatible structure modifiers:%s', sprintf( ' %s', args.orig ) );
end    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Replicate structure for N-D arrays                                       %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if length( sz ) > 2,
    S = cvx_replicate_structure( S, sz( 3 : end ) );
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Display the structure if called with no output arguments                 %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if nargout == 0,
    [ii,jj,vv] = find( S );
    if isempty(sz), sz = [1,1]; end
    Z = reshape( full( sparse( jj, 1, ii .* vv, prod(sz), 1 ) ), sz );
    temp = sprintf( ',%d', sz );
    fprintf( '\n%s(%s)', name{1}, temp(2:end) );
    for k = 2 : nargs,
        if any( strcmp(orig{k},itypes) )
            fprintf( ' [%s]', orig{k} );
        else
            fprintf( ' %s', orig{k} );
        end
    end
    fprintf( '\n\n' );
    fmt = get(0,'format');
    set(0,'format','rational');
    disp( Z );
    set(0,'format',fmt);
    clear S
end

% Copyright 2005-2014 CVX Research, Inc.
% See the file LICENSE.txt for orig copyright information.
% The command 'cvx_where' will show where this file is located.

function [ y, symm ] = cvx_s_lower_bidiagonal( m, n, symm )

%CVX_S_LOWER_BIDIAGONAL Lower bidiagonal matrices.

[ y, symm ] = cvx_s_banded( m, n, symm, 1, 0 );

% Copyright 2005-2014 CVX Research, Inc. 
% See the file LICENSE.txt for full copyright information.
% The command 'cvx_where' will show where this file is located.

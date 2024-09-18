program simple_test_eigh
include 'simple_lib.f08'
integer, parameter :: N = 5, N_EIGS = 3
integer  :: i
real(dp) :: mat(N, N), eigvals(N_EIGS), eigvecs(N,N_EIGS)
mat(:,1) = [ 0.67, 0.00, 0.00, 0.00, 0.00]
mat(:,2) = [-0.20, 3.82, 0.00, 0.00, 0.00]
mat(:,3) = [ 0.19,-0.13, 3.27, 0.00, 0.00]
mat(:,4) = [-1.06, 1.06, 0.11, 5.86, 0.00]
mat(:,5) = [ 0.46,-0.48, 1.10,-0.98, 3.54]
call eigh( N, mat, N_EIGS, eigvals, eigvecs )
print *, 'Selected eigenvalues', eigvals
print *, 'Selected eigenvectors (stored columnwise)'
do i = 1, N
    print *, eigvecs(i,:)
enddo
end program simple_test_eigh
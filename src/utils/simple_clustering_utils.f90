! Tools and metrics for clustering analysis
module simple_clustering_utils
use simple_kmedoids, only: kmedoids
use simple_aff_prop, only: aff_prop
include 'simple_lib.f08'
implicit none

public :: cluster_dmat, extract_dmat, aggregate, silhouette_score, DBIndex, DunnIndex
private
#include "simple_local_flags.inc"

contains

    subroutine cluster_dmat( dmat, algorithm, nclust, i_medoids, labels, ap_pref )
        real,                 intent(in)    :: dmat(:,:)
        character(len=*),     intent(in)    :: algorithm
        integer,              intent(inout) :: nclust
        integer, allocatable, intent(inout) :: i_medoids(:), labels(:)
        real,    optional,    intent(in)    :: ap_pref
        real,    allocatable :: smat(:,:)
        type(kmedoids)       :: kmed
        type(aff_prop)       :: aprop
        integer :: n
        real    :: pref, simsum
        n = size(dmat, dim=1)
        if( allocated(i_medoids) ) deallocate(i_medoids)
        if( allocated(labels)    ) deallocate(labels)
        select case(trim(algorithm))
            case('aprop')
                write(logfhandle,'(A)') '>>> CLUSTERING DISTANCE MATRIX WITH AFFINITY PROPAGATION'
                smat = dmat2smat(dmat)
                pref = 0. ! assuming normalized distance matrix, pref=0. because this is the minimal score
                if( present(ap_pref) ) pref = ap_pref
                call aprop%new(n, smat, pref=pref)
                call aprop%propagate(i_medoids, labels, simsum)
                call aprop%kill
                nclust = size(i_medoids)
                write(logfhandle,'(A,I3)') '>>> # CLUSTERS FOUND BY AFFINITY PROPAGATION (AP): ', nclust
            case('kmed')
                write(logfhandle,'(A)') '>>> CLUSTERING DISTANCE MATRIX WITH K-MEDOIDS'
                if( nclust < 2 ) THROW_HARD('Invalid nclust input')
                call kmed%new(n, dmat, nclust)
                call kmed%init
                call kmed%cluster
                allocate(labels(n), i_medoids(nclust), source=0)
                call kmed%get_labels(labels)
                call kmed%get_medoids(i_medoids)
                call kmed%kill
        end select
    end subroutine cluster_dmat

    subroutine extract_dmat( dmat, mask, inds, dmat_sub ) 
        real,                 intent(in)    :: dmat(:,:)
        logical,              intent(in)    :: mask(:) 
        integer, allocatable, intent(inout) :: inds(:)
        real,    allocatable, intent(inout) :: dmat_sub(:,:)
        integer, allocatable :: itmp(:)
        integer :: n, i, j, nsub
        n = size(dmat, dim=1)
        if( n /= size(mask) ) THROW_HARD('Incongrouent array dimensions, labels must have same dimension as symmetric dmat')
        nsub = count(mask)
        if( allocated(dmat_sub) ) deallocate(dmat_sub)
        allocate(dmat_sub(nsub,nsub), source=0.)
        if( allocated(inds) ) deallocate(inds)
        allocate(itmp(n), source=(/(i,i=1,n)/))
        inds = pack(itmp, mask=mask)    
        do i = 1, nsub - 1
            do j = i + 1, nsub
                dmat_sub(i,j) = dmat(inds(i),inds(j))
                dmat_sub(j,i) = dmat_sub(i,j)
            end do
        end do
        call normalize_minmax(dmat_sub)
    end subroutine extract_dmat

    !>  \brief Given labelling into k partitions and corresponding distance matrix iteratively
    !          combines the pair of clusters with lowest average inter-cluster distance,
    !          and produces labelling for partitions in [1;k] (1 & k for convenience)
    subroutine aggregate( labels, distmat, labelsmat )
        integer,              intent(in)    :: labels(:)
        real,                 intent(in)    :: distmat(:,:)
        integer, allocatable, intent(inout) :: labelsmat(:,:)
        real,    allocatable :: clmat(:,:)
        integer, allocatable :: iinds(:), jinds(:)
        real    :: d
        integer :: pair(2), nc, nl, cl, i,j,k, ni, aggc, oldc
        nl = size(labels)
        nc = maxval(labels) ! 1-base numbering assumed
        allocate(labelsmat(nl,nc), source=0)
        labelsmat(:,1)  = 1
        labelsmat(:,nc) = labels
        do cl = nc-1,2,-1
            ! average inter-cluster distance
            allocate(clmat(cl+1,cl+1),source=huge(d))
            do i = 1,cl
                iinds = pack((/(k,k=1,nl)/),mask=labelsmat(:,cl+1)==i)
                ni = size(iinds)
                do j = i+1, cl+1
                    jinds = pack((/(k,k=1,nl)/),mask=labelsmat(:,cl+1)==j)
                    d = 0.
                    do k = 1,ni
                        d = d + sum(distmat(iinds(k),jinds(:)))
                    enddo
                    clmat(i,j) = d / real(ni*size(jinds))
                enddo
            enddo
            ! select pait of clusters to aggregate
            pair = minloc(clmat)
            aggc = minval(pair)
            oldc = maxval(pair)
            ! update labelling
            labelsmat(:,cl) = labelsmat(:,cl+1)
            where(labelsmat(:,cl) == oldc) labelsmat(:,cl) = aggc
            where(labelsmat(:,cl) >  oldc) labelsmat(:,cl)  = labelsmat(:,cl)-1
            deallocate(clmat,iinds,jinds)
        enddo
    end subroutine aggregate

    ! Average silhouette score, for instance https://en.wikipedia.org/wiki/Silhouette_(clustering)
    ! -1 <= SC <= 1, higher SC => better clustering
    real function silhouette_score( labels, distmat )
        integer, intent(in)  :: labels(:)
        real,    intent(in)  :: distmat(:,:)    ! Precomputed distance matrix
        integer, allocatable :: inds(:)
        real    :: a,b,s
        integer :: i,j,k, nl, nc, ni
        nl = size(labels)
        nc = maxval(labels)
        if( nl /= size(distmat,dim=1) ) THROW_HARD('Inconsistent dimensions 1; silhouette_score')
        if( nl /= size(distmat,dim=2) ) THROW_HARD('Inconsistent dimensions 2; silhouette_score')
        s  = 0.
        do i = 1,nl
            inds = pack((/(j,j=1,nl)/),mask=labels==labels(i))
            ni   = size(inds)
            if( ni == 1 ) cycle
            a    = sum(distmat(i,inds)) / real(ni-1) ! -1 because i is part of the set, and d(i,i)=0
            b    = huge(b)
            do k = 1,nc
                if( labels(i)==k ) cycle
                inds = pack((/(j,j=1,nl)/),mask=labels==k)
                if( .not.allocated(inds) ) cycle
                if( size(inds)==0 ) cycle
                b = min(b, sum(distmat(i,inds)) / real(size(inds)))
            enddo
            s = s + (b-a) / max(a,b)
        enddo
        silhouette_score = s / real(nl)
    end function silhouette_score

    ! DaviesBouldin Index, lower the better
    real function DBIndex( labels, feats )
        integer, intent(in)  :: labels(:)
        real,    intent(in)  :: feats(:,:)
        real,    allocatable :: a(:,:), m(:,:), s(:)
        integer, allocatable :: inds(:)
        real    :: dk
        integer :: i,j,k, nl, nc, ni, nrows, ncols
        nl    = size(labels)
        nc    = maxval(labels)
        nrows = size(feats,dim=1)
        if( nrows /= nl ) THROW_HARD('Invalid dimensions! DBIndex')
        ncols = size(feats,dim=2)
        allocate(a(nc,ncols),s(nc),source=0.)
        do k = 1,nc
            inds = pack((/(i,i=1,nl)/),mask=labels==k)
            ni   = size(inds)
            if( ni == 0 ) cycle
            ! centroid
            a(k,:) = 0.
            do i = 1,ni
                a(k,:) = a(k,:) + feats(inds(i),:)
            enddo
            a(k,:) = a(k,:) / real(ni)
            ! intra cluster distance
            s(k) = 0.
            do i = 1,ni
                s(k) = s(k) + sum((feats(inds(i),:)-a(k,:))**2)
            enddo
            s(k) = sqrt(s(k)/real(ni))
        enddo
        ! inter cluster distance
        allocate(m(nc,nc),source=0.)
        do i = 1,nc
            do j = i+1,nc
                m(i,j) = sqrt(sum((a(i,:)-a(j,:))**2))
                m(j,i) = m(i,j)
            enddo
        enddo
        dbindex = 0.
        do k = 1,nc
            dk = -huge(dk)
            do i = 1,nc
                if( i==k ) cycle
                dk = max(dk, (s(i)+s(k)) / m(i,k))
            enddo
            dbindex = dbindex + dk
        enddo
        dbindex = dbindex / real(nc)
    end function DBIndex

    real function DunnIndex( labels, D )
        integer, intent(in)  :: labels(:)
        real,    intent(in)  :: D(:,:)      ! precomputed distance matrix
        real,    allocatable :: distmat(:,:)
        integer, allocatable :: distpops(:,:) 
        real    :: mininter, maxintra
        integer :: i,j,li,lj,nk,nl
        nl = size(labels)
        nk = maxval(labels)
        if( nl /= size(D,dim=1) ) THROW_HARD('Inconsistent dimensions 1; DunnIndex')
        if( nl /= size(D,dim=2) ) THROW_HARD('Inconsistent dimensions 2; DunnIndex')
        allocate(distmat(nk,nk),distpops(nk,nk))
        ! intra/inter cluster mean distance
        distpops = 0
        distmat  = 0.
        do i = 1,nl
            li = labels(i)
            do j = i+1,nl
                lj = labels(j)
                distmat(li,lj)  = distmat(li,lj) + D(i,j)
                distpops(li,lj) = distpops(li,lj) + 1
            enddo
        enddo
        where( distpops > 1 ) distmat = distmat / real(distpops)
        mininter = huge(mininter)
        maxintra = -1.
        do i=1,nk
            do j=i,nk
                if( i==j )then
                    maxintra = max(distmat(i,j), maxintra)
                else
                    mininter = min(distmat(i,j), mininter)
                endif
            enddo
        enddo
        DunnIndex = mininter / maxintra
    end function DunnIndex

end module simple_clustering_utils

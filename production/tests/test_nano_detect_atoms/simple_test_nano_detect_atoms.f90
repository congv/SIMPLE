module nano_picker_utils
    include 'simple_lib.f08'
    use simple_image
    use simple_atoms
    use simple_parameters

    implicit none

    contains 

    subroutine window_slim_3D( img_in, coord, box, img_out)
        class(image), intent(in)    :: img_in
        integer,      intent(in)    :: coord(3), box
        class(image), intent(inout) :: img_out
        integer :: fromc(3), toc(3)
        real, allocatable :: img_in_rmat(:,:,:)
        allocate(img_in_rmat,source=img_in%get_rmat())
        fromc = coord + 1
        toc   = fromc + box - 1 
        call img_out%set_rmat(img_in_rmat(fromc(1):toc(1), fromc(2):toc(2), fromc(3):toc(3)), ft=.false.)
        deallocate(img_in_rmat) 
    end subroutine window_slim_3D

    subroutine find_closest( coords_1, coords_2, length_1, length_2, distances, filename )
        integer,                    intent(in)  :: length_1, length_2
        real,                       intent(in)  :: coords_1(3,length_1), coords_2(3,length_2)
        real,                       intent(out) :: distances(length_1)
        character(len=*), optional, intent(in)  :: filename
        integer :: i, j, min_loc(1)
        real :: closest_coord(3)
        real, allocatable :: dists(:)
        real :: min_dist

        if (present(filename)) then
            open(unit=22, file=filename)
        else
            open(unit=22, file='combined_coords.csv')
        end if

        do i = 1, length_1
            allocate(dists(length_2))
            do j = 1, length_2
                dists(j) = euclid(real(coords_1(:,i)),real(coords_2(:,j)))
            end do
            min_loc = minloc(dists)
            min_dist = minval(dists)
            distances(i) = min_dist
            closest_coord = coords_2(:,min_loc(1))
            write(22,'(7(f8.3))') coords_1(1,i), coords_1(2,i), coords_1(3,i), closest_coord(1), closest_coord(2), closest_coord(3), min_dist
            deallocate(dists)
        end do

        close(22)
    end subroutine find_closest

    subroutine write_centers(fname, coords, smpd)
        character(len=*),           intent(in)    :: fname
        real,                       intent(in)    :: coords(:,:)
        real,                       intent(in)    :: smpd
        type(atoms) :: centers_pdb
        integer     :: cc
        call centers_pdb%new(size(coords, dim = 1), dummy=.true.)
        do cc = 1, size(coords, dim = 1)
            call centers_pdb%set_name(cc,params_glob%element)
            call centers_pdb%set_element(cc,params_glob%element)
            call centers_pdb%set_coord(cc,coords(cc,:)*smpd)
            !call centers_pdb%set_beta(cc,nano%atominfo(cc)%valid_corr) ! use per atom valid corr
            call centers_pdb%set_resnum(cc,cc)
        enddo
        call centers_pdb%writepdb(fname)
    end subroutine write_centers

    function avg_loc_sdev_3D(img, winsz) result(asdev)
        type(image), intent(in) :: img
        integer,     intent(in) :: winsz
        integer           :: img_ldim(3), i, j, k, ir(2), jr(2), kr(2), npix, isz, jsz, ksz
        real              :: avg, asdev
        real, allocatable :: rmat(:,:,:), sdevs(:,:,:)
        img_ldim = img%get_ldim()
        allocate( rmat(img_ldim(1),img_ldim(2),img_ldim(3)))
        allocate(sdevs(img_ldim(1),img_ldim(2),img_ldim(3)))
        rmat = img%get_rmat()
        do i = 1, img_ldim(1)
            ir(1) = max(1,           i-winsz)
            ir(2) = min(img_ldim(1), i+winsz)
            isz   = ir(2) - ir(1) + 1
            do j = 1, img_ldim(2)
                jr(1) = max(1,           j-winsz)
                jr(2) = min(img_ldim(2), j+winsz)
                jsz   = jr(2) - jr(1) + 1
                do k = 1, img_ldim(3)
                    kr(1)        = max(1,           k-winsz)
                    kr(2)        = min(img_ldim(3), k+winsz)
                    ksz          = kr(2) - kr(1) + 1
                    npix         = isz * jsz * ksz
                    avg          = sum(rmat(ir(1):ir(2),jr(1):jr(2),kr(1):kr(2))) / real(npix)
                    sdevs(i,j,k) = sqrt(sum((rmat(ir(1):ir(2),jr(1):jr(2),kr(1):kr(2))-avg)**2.0) / real(npix - 1))
                end do
            end do
        end do
        asdev = sum(sdevs) / real(img_ldim(1) * img_ldim(2) * img_ldim(3))
        deallocate(rmat,sdevs)
    end function avg_loc_sdev_3D

end module nano_picker_utils

module nano_detect_atoms
    !$ use omp_lib
    !$ use omp_lib_kinds
    include 'simple_lib.f08'
    use simple_image
    use simple_atoms
    use simple_nanoparticle
    use simple_parameters
    use nano_picker_utils
    use simple_math
    use simple_linalg
    use simple_nanoparticle_utils
    use simple_defs_atoms
    use simple_stat

    implicit none
    
    type :: nano_picker
        private
        character(len=2)   :: element
        integer :: boxsize, ldim(3), nxyz_offset(3), offset, peak_thres_level
        integer, allocatable :: positions(:,:), inds_offset(:,:,:)
        type(image) :: simulated_atom, nano_img
        type(image), allocatable :: convolved_atoms(:)
        real :: smpd, thres
        real, allocatable :: box_scores(:,:,:), loc_sdevs(:,:,:)

    contains
        procedure :: new
        procedure :: simulate_atom
        procedure :: setup_iterators
        procedure :: match_boxes
        procedure :: identify_threshold
        procedure :: center_filter
        procedure :: distance_filter
        procedure :: cluster_filter
        procedure :: remove_outliers
        procedure :: find_centers
        procedure :: write_boximgs
        procedure :: compare_pick
        procedure :: kill

    end type nano_picker

    contains

    subroutine new(self, smpd, element, filename, peak_thres_level)
        class(nano_picker), intent(inout) :: self
        real, intent(in)                  :: smpd
        character(len=*), intent(in)      :: element
        character(len=100), intent(in)    :: filename
        integer, intent(in)               :: peak_thres_level
        type(nanoparticle)       :: nano
        type(parameters), target :: params
        self%smpd = smpd
        self%element = element
        ! retrieve nano_img from filename and find ldim
        params_glob => params
        params_glob%element = self%element
        params_glob%smpd = self%smpd
        call nano%new(filename)
        call nano%get_img(self%nano_img)
        self%ldim = self%nano_img%get_ldim()
        self%peak_thres_level = peak_thres_level
    end subroutine new

    subroutine simulate_atom(self)
        class(nano_picker), intent(inout) :: self
        real        :: radius
        integer     :: Z, ldim_box(3)
        type(atoms) :: atom
        logical     :: l_err_atom
        call get_element_Z_and_radius(self%element, Z, radius)
        call atom%new(1)
        call atom%set_element(1,trim(self%element))
        self%boxsize = round2even(radius / self%smpd) * 2
        ldim_box = [self%boxsize,self%boxsize,self%boxsize]
        call atom%set_coord(1,(self%smpd*real(ldim_box)/2.)) ! make sure atom is in center of box
        call self%simulated_atom%new(ldim_box,self%smpd)
        call atom%convolve(self%simulated_atom, cutoff=8*self%smpd)
        call self%simulated_atom%write('simulated_atom.mrc')
        call self%simulated_atom%prenorm4real_corr(l_err_atom)
    end subroutine simulate_atom

    subroutine setup_iterators(self, offset)
        class(nano_picker), intent(inout) :: self
        integer,            intent(in)    :: offset
        integer :: nxyz(3), xind, yind, zind, nboxes
        ! set up picking infrastructure
        self%offset = offset
        nxyz = self%ldim - self%boxsize
        self%nxyz_offset = 0
        nboxes=0
        ! find number of boxes
        do xind = 0, nxyz(1), self%offset
            self%nxyz_offset(1) = self%nxyz_offset(1) + 1
            self%nxyz_offset(2) = 0
            do yind = 0, nxyz(2), self%offset
                self%nxyz_offset(2) = self%nxyz_offset(2) + 1
                self%nxyz_offset(3) = 0
                do zind = 0, nxyz(3), offset
                    self%nxyz_offset(3) = self%nxyz_offset(3) + 1
                    nboxes = nboxes + 1
                end do
            end do
        end do
        ! set up positions and inds_offset
        allocate(self%positions(nboxes,3), source = 0)
        allocate(self%inds_offset(self%nxyz_offset(1),self%nxyz_offset(2),self%nxyz_offset(3)), source=0)
        self%nxyz_offset = 0
        nboxes = 0
        do xind = 0, nxyz(1), self%offset
            self%nxyz_offset(1) = self%nxyz_offset(1) + 1
            self%nxyz_offset(2) = 0
            do yind = 0, nxyz(2), self%offset
                self%nxyz_offset(2) = self%nxyz_offset(2) + 1
                self%nxyz_offset(3) = 0
                do zind = 0, nxyz(3), self%offset
                    self%nxyz_offset(3) = self%nxyz_offset(3) + 1
                    nboxes = nboxes + 1
                    self%positions(nboxes,:) = [xind,yind,zind]
                    self%inds_offset(self%nxyz_offset(1),self%nxyz_offset(2),self%nxyz_offset(3)) = nboxes
                end do
            end do
        end do
        allocate(self%box_scores(self%nxyz_offset(1),self%nxyz_offset(2),self%nxyz_offset(3)), source = -1.)
        allocate(self%loc_sdevs( self%nxyz_offset(1),self%nxyz_offset(2),self%nxyz_offset(3)), source = -1.)
    end subroutine setup_iterators

    subroutine match_boxes(self)
        class(nano_picker), intent(inout) :: self
        type(image), allocatable :: boximgs(:)
        integer                  :: xoff, yoff, zoff, pos(3), ithr, nthr
        logical                  :: l_err_box
        ! construct array of boximgs
        !$ nthr = omp_get_max_threads()
        allocate(boximgs(nthr))
        do ithr = 1,nthr
            call boximgs(ithr)%new([self%boxsize,self%boxsize,self%boxsize],self%smpd)
        end do
        ! iterate through positions in nanoparticle image, compare to simulated atom 
        !$omp parallel do schedule(static) collapse(3) default(shared) private(xoff,yoff,zoff,ithr,pos,l_err_box) proc_bind(close)
        do xoff = 1, self%nxyz_offset(1)
            do yoff = 1, self%nxyz_offset(2)
                do zoff = 1, self%nxyz_offset(3)
                    ithr = omp_get_thread_num() + 1
                    pos = self%positions(self%inds_offset(xoff,yoff,zoff),:)
                    call window_slim_3D(self%nano_img, pos, self%boxsize, boximgs(ithr))
                    call boximgs(ithr)%prenorm4real_corr(l_err_box)
                    self%box_scores(xoff,yoff,zoff) = self%simulated_atom%real_corr_prenorm(boximgs(ithr))
                    self%loc_sdevs( xoff,yoff,zoff) = avg_loc_sdev_3D(boximgs(ithr),self%offset)
                end do 
            end do 
        end do
        !$omp end parallel do
        ! kill boximgs
        do ithr = 1,nthr
            call boximgs(ithr)%kill
        end do
        deallocate(boximgs)
    end subroutine match_boxes

    subroutine identify_threshold(self,min_thres)
        class(nano_picker), intent(inout) :: self
        real, optional,     intent(in)    :: min_thres
        real,    allocatable :: tmp(:)
        ! find peak thresholding value
        if (present(min_thres)) then
            tmp = pack(self%box_scores, mask=(self%box_scores > min_thres))
        else ! idk if this is something that makes sense to do..
            tmp = pack(self%box_scores, mask=(self%box_scores > -1 + 1e-10))
        end if
        call detect_peak_thres(size(tmp), size(tmp), self%peak_thres_level, tmp, self%thres)
        print *, 'Peak threshold is ', self%thres
        deallocate(tmp)
    end subroutine identify_threshold

    subroutine center_filter(self)
        class(nano_picker), intent(inout) :: self
        real, allocatable        :: scores_cen(:,:,:)
        integer                  :: xoff, yoff, zoff, pos(3), npeaks, ithr, nthr
        type(image), allocatable :: boximgs(:)
        ! construct array of boximgs
        !$ nthr = omp_get_max_threads()
        allocate(boximgs(nthr))
        do ithr = 1,nthr
            call boximgs(ithr)%new([self%boxsize,self%boxsize,self%boxsize],self%smpd)
        end do
        allocate(scores_cen(self%nxyz_offset(1), self%nxyz_offset(2), self%nxyz_offset(3)))
        !$omp parallel do schedule(static) collapse(3) default(shared) private(xoff,yoff,zoff,ithr,pos) proc_bind(close)
        do xoff = 1, self%nxyz_offset(1)
            do yoff = 1, self%nxyz_offset(2)
                do zoff = 1, self%nxyz_offset(3)
                if( self%box_scores(xoff,yoff,zoff) >= self%thres )then
                    ithr = omp_get_thread_num() + 1
                    pos  = self%positions(self%inds_offset(xoff,yoff,zoff),:)
                    call window_slim_3D(self%nano_img, pos, self%boxsize, boximgs(ithr))
                    scores_cen(xoff, yoff, zoff) = boximgs(ithr)%box_cen_arg(boximgs(ithr))
                else
                    scores_cen(xoff,yoff,zoff) = real(self%offset) + 1.
                endif
                end do
            end do
        end do
        !$omp end parallel do
        ! kill boximgs
        do ithr = 1,nthr
            call boximgs(ithr)%kill
        end do
        deallocate(boximgs)
        print *, 'NPEAKS BEFORE CENTER FILTER = ', count(self%box_scores >= self%thres)
        npeaks = count(scores_cen <= real(self%offset))
        where( scores_cen <= real(self%offset))
            ! there's a peak
        elsewhere
            self%box_scores = -1.
        endwhere
        print *, 'NPEAKS AFTER CENTER FILTER = ', npeaks
        deallocate(scores_cen)
    end subroutine center_filter

    subroutine distance_filter(self, dist_thres)
        class(nano_picker), intent(inout) :: self
        real,   optional,   intent(in)    :: dist_thres
        real :: dist_thres_here, dist
        integer :: nbox, ibox, jbox, xoff, yoff, zoff, npeaks, ipeak, loc
        integer, allocatable :: pos_inds(:)
        real, allocatable :: pos_scores(:)
        logical, allocatable :: mask(:), selected_pos(:)
        logical :: is_peak
        character(len=8) :: crystal_system
        ! distance threshold
        if (present(dist_thres)) then
            dist_thres_here = dist_thres
        else
            dist_thres_here = self%offset
        end if
        pos_inds   = pack(self%inds_offset(:,:,:),  mask=self%box_scores(:,:,:) >= self%thres)
        pos_scores = pack(self%box_scores(:,:,:),   mask=self%box_scores(:,:,:) >= self%thres)
        nbox       = size(pos_inds)
        allocate(mask(nbox),         source=.false.)
        allocate(selected_pos(nbox), source=.true. )
        do ibox = 1, nbox
            mask = .false.
            ! identify boxes in neighborhood
            !$omp parallel do schedule(static) default(shared) private(jbox, dist) proc_bind(close)
            do jbox = 1, nbox
                dist = euclid(real(self%positions(pos_inds(ibox),:)),real(self%positions(pos_inds(jbox),:)))
                if( dist <= dist_thres_here ) mask(jbox) = .true.
            end do
            !$omp end parallel do
            ! find highest correlation score in neighborhood
            loc = maxloc(pos_scores, mask=mask, dim=1)
            ! eliminate all but the best
            mask(loc) = .false.
            where( mask ) selected_pos = .false.
        end do
        npeaks = count(selected_pos)
        print *, 'NPEAKS BEFORE DISTANCE FILTER = ', nbox
        print *, 'NPEAKS AFTER DISTANCE FILTER = ', npeaks
        ! update packed arrays
        pos_inds   = pack(pos_inds,   mask=selected_pos)
        pos_scores = pack(pos_scores, mask=selected_pos)
        ! update box scores
        !$omp parallel do schedule(static) collapse(3) default(shared) private(xoff,yoff,zoff,is_peak,ipeak)
        do xoff = 1, self%nxyz_offset(1)
            do yoff = 1, self%nxyz_offset(2)
                do zoff = 1, self%nxyz_offset(3)
                    is_peak = .false.
                    do ipeak = 1,npeaks
                        if( pos_inds(ipeak) == self%inds_offset(xoff,yoff,zoff) )then
                            is_peak = .true.
                            exit
                        endif
                    end do
                    if( .not. is_peak ) self%box_scores(xoff,yoff,zoff) = -1.
                end do
            end do
        end do
        !$omp end parallel do
        deallocate(pos_inds, pos_scores, mask, selected_pos)
    end subroutine distance_filter

    ! implementation of Rodriguez & Laio (2014): "Clustering by fast search and find density of peaks"
    subroutine cluster_filter(self,dist_thres)
        class(nano_picker), intent(inout) :: self
        real,               intent(in)    :: dist_thres
        real, allocatable    :: deltas(:), pos_scores(:), upper_half_deltas(:), lower_half_deltas(:)
        real                 :: dist, min_dist, median_d, Q3_d, Q1_d, IQR_d, max_box_score, score
        integer, allocatable :: pos_inds(:), rhos_higher_inds(:), rhos(:), cluster_inds(:), clusters(:), this_clusters_boxes(:)
        integer              :: nbox, ibox, jbox, n_rhos_higher, xoff, yoff, zoff
        integer              :: ipeak, npeaks, nclusters, icluster, box_cluster, box_index(3), this_clusters_size, box_id(1)
        logical, allocatable :: mask(:)
        logical              :: is_peak
        pos_inds   = pack(self%inds_offset(:,:,:),  mask=self%box_scores(:,:,:) >= self%thres)
        pos_scores = pack(self%box_scores(:,:,:),   mask=self%box_scores(:,:,:) >= self%thres)
        nbox       = size(pos_inds)
        print *, 'NPEAKS BEFORE CLUSTER FILTER = ', nbox
        allocate(rhos(nbox),   source = 0 )
        allocate(deltas(nbox), source = 0.)
        allocate(clusters(nbox))
        ! first loop calculates rho values for all boxes
        do ibox = 1, nbox
            ! find distances to all other boxes
            do jbox = 1, nbox
                dist = euclid(real(self%positions(pos_inds(ibox),:)),real(self%positions(pos_inds(jbox),:)))
                if (dist < dist_thres) rhos(ibox) = rhos(ibox) + 1
            end do
        end do
        ! second loop finds min distance between each box and the boxes with higher rho values than it (delta value)
        do ibox = 1, nbox
            min_dist = 1000
            rhos_higher_inds = pack(pos_inds(:), rhos(:) > rhos(ibox))
            n_rhos_higher = size(rhos_higher_inds)
            ! iterate through only the rhos with higher rho values
            do jbox = 1, n_rhos_higher
                dist = euclid(real(self%positions(pos_inds(ibox),:)),real(self%positions(rhos_higher_inds(jbox),:)))
                if (dist < min_dist) min_dist = dist
            end do
            deltas(ibox) = min_dist
            deallocate(rhos_higher_inds)
        end do
        ! the boxes with high delta values are centers of clusters
        median_d = median(deltas)
        upper_half_deltas = pack(deltas, mask=deltas(:) > median_d)
        lower_half_deltas = pack(deltas, mask=deltas(:) < median_d)
        Q3_d = median(upper_half_deltas)
        Q1_d = median(lower_half_deltas)
        IQR_d = Q3_d - Q1_d
        deallocate(upper_half_deltas, lower_half_deltas)
        ! find positions with outlier delta scores - these are cluster centers
        cluster_inds = pack(pos_inds, mask= deltas(:) >= Q3_d + (1.5*IQR_d))
        nclusters = size(cluster_inds)
        print *, 'NPEAKS AFTER CLUSTER FILTER = ', nclusters
        ! assign all boxes to a cluster
        ! ultimately want to pick box with highest box score within each cluster
        do ibox = 1, nbox
            min_dist = 1000
            do icluster = 1, nclusters
                dist = euclid(real(self%positions(pos_inds(ibox),:)),real(self%positions(cluster_inds(icluster),:)))
                if (dist < min_dist) then
                    min_dist = dist
                    box_cluster = icluster
                end if
            end do
            clusters(ibox) = box_cluster !this array contains integer id of the cluster each box belongs to
        end do
        ! clustering is finished
        ! after assigning each box to a cluster, iterate through all clusters and find box with highest box score in cluster
        allocate(mask(nbox)) 
        mask = .false.
        do icluster = 1, nclusters
            this_clusters_boxes = pack(pos_inds, mask=clusters(:) == icluster)
            this_clusters_size = size(this_clusters_boxes)
            max_box_score = 0
            do ibox = 1, this_clusters_size
                box_index = findloc(array=self%inds_offset, value=this_clusters_boxes(ibox))
                score = self%box_scores(box_index(1), box_index(2), box_index(3))
                if (score > max_box_score) then
                    max_box_score = score
                    ! find position in mask
                    box_id = findloc(pos_inds, this_clusters_boxes(ibox))
                end if
            end do
            mask(box_id(1)) = .true.
            deallocate(this_clusters_boxes)
        end do
        ! update box scores
        npeaks = count(mask)
        pos_inds   = pack(pos_inds,   mask=mask)
        !$omp parallel do schedule(static) collapse(3) default(shared) private(xoff,yoff,zoff,is_peak,ipeak)
        do xoff = 1, self%nxyz_offset(1)
            do yoff = 1, self%nxyz_offset(2)
                do zoff = 1, self%nxyz_offset(3)
                    is_peak = .false.
                    do ipeak = 1,npeaks
                        if( pos_inds(ipeak) == self%inds_offset(xoff,yoff,zoff) )then
                            is_peak = .true.
                            exit
                        endif
                    end do
                    if( .not. is_peak ) self%box_scores(xoff,yoff,zoff) = -1.
                end do
            end do
        end do
        !$omp end parallel do  
    end subroutine cluster_filter

    subroutine remove_outliers(self, ndev)
        class(nano_picker), intent(inout) :: self
        real,               intent(in)    :: ndev
        real, allocatable :: tmp(:)
        real              :: avg, sdev, t
        integer           :: npeaks, xoff, yoff, zoff
        tmp = pack(self%loc_sdevs, mask = self%box_scores(:,:,:) >= self%thres .and. self%loc_sdevs(:,:,:) > 0.)
        call avg_sdev(tmp, avg, sdev)
        t = avg + ndev * sdev
        npeaks = count(tmp < t)
        print *, 'NPEAKS AFTER REMOVE OUTLIERS = ', npeaks
        ! update box scores
        !$omp parallel do schedule(static) collapse(3) default(shared) private(xoff,yoff,zoff) proc_bind(close)
        do xoff = 1, self%nxyz_offset(1)
            do yoff = 1, self%nxyz_offset(2)
                do zoff = 1, self%nxyz_offset(3)
                    if (self%loc_sdevs(xoff,yoff,zoff) < t) then
                        ! it is a peak
                    else
                        self%box_scores(xoff,yoff,zoff) = -1
                    end if
                end do
            end do
        end do
        !$omp end parallel do
    end subroutine remove_outliers

    ! input filename with no extension
    subroutine find_centers(self,filename)
        class(nano_picker),         intent(inout) :: self
        character(len=*), optional, intent(in)    :: filename
        integer,     allocatable :: pos_inds(:)
        real,        allocatable :: coords(:,:)
        type(image), allocatable :: atms_array(:)
        integer :: nbox, iimg, pos(3)
        ! make array of images containing the images of identified atoms and extract coordinates of peaks
        pos_inds = pack(self%inds_offset(:,:,:),  mask=self%box_scores(:,:,:) >= self%thres)
        nbox = size(pos_inds, dim=1)
        allocate(coords(nbox,3))
        allocate(atms_array(nbox))
        allocate(self%convolved_atoms(nbox))
        call self%simulated_atom%fft()
        do iimg = 1, nbox
            pos = self%positions(pos_inds(iimg),:)
            call atms_array(iimg)%new([self%boxsize,self%boxsize,self%boxsize],self%smpd)
            call self%convolved_atoms(iimg)%new([self%boxsize,self%boxsize,self%boxsize],self%smpd)
            call window_slim_3D(self%nano_img, pos, self%boxsize, atms_array(iimg))
            call atms_array(iimg)%fft()
            self%convolved_atoms(iimg) = atms_array(iimg)%conjg() * self%simulated_atom
            call self%convolved_atoms(iimg)%ifft()
            call atms_array(iimg)%ifft()
            ! want coordinates of atoms to be at the center of the images
            call self%convolved_atoms(iimg)%norm_minmax
            call self%convolved_atoms(iimg)%masscen(coords(iimg,:)) 
            coords(iimg,:) = coords(iimg,:) + real(self%convolved_atoms(iimg)%get_ldim())/2. + pos !adjust center by size and position of box
        end do
        call self%simulated_atom%ifft()
        if (present(filename)) then
            call write_centers(filename,coords,self%smpd)
        else
            call write_centers('test_atomic_centers',coords,self%smpd)
        end if
        deallocate(atms_array)
        deallocate(coords)
        deallocate(pos_inds)
    end subroutine find_centers

    subroutine write_boximgs(self, foldername)
        class(nano_picker),          intent(inout) :: self
        character(len=*), optional,  intent(in)    :: foldername
        integer              :: iimg, nbox
        integer, allocatable :: pos_inds(:)
        pos_inds   = pack(self%inds_offset(:,:,:),  mask=self%box_scores(:,:,:) >= self%thres)
        nbox = size(pos_inds, dim=1)
        do iimg = 1, nbox
            if (present(foldername)) then 
                call self%convolved_atoms(iimg)%write(trim(adjustl(foldername))//'/boximg_'//trim(int2str(iimg))//'.mrc')
            else
                call self%convolved_atoms(iimg)%write('boximgs/boximg_'//trim(int2str(iimg))//'.mrc')
            end if
        end do
        deallocate(pos_inds)
    end subroutine write_boximgs

    ! input both pdbfile_* with .pdb extension
    subroutine compare_pick(self, pdbfile_ref, pdbfile_exp )
        class(nano_picker),         intent(inout) :: self
        character(len=*),           intent(in)    :: pdbfile_ref
        character(len=*), optional, intent(in)    :: pdbfile_exp
        real, allocatable :: pdb_ref_coords(:,:), pdb_exp_coords(:,:), distances(:)
        integer           :: iostat
        call read_pdb2matrix(trim(pdbfile_ref), pdb_ref_coords)
        if (present(pdbfile_exp)) then 
            call read_pdb2matrix(trim(pdbfile_exp),pdb_exp_coords)
        else
            open(unit = 40, file='test_atomic_centers.pdb', iostat=iostat)
            if (iostat /= 0) then
                print *, 'compare_pick: test_atomic_centers.pdb does not exist, please enter valid filename for pdbfile_exp'
                return
            end if
            call read_pdb2matrix('test_atomic_centers.pdb',pdb_exp_coords)
        end if
        allocate(distances(max(size(pdb_ref_coords,dim=2),size(pdb_exp_coords,dim=2))))
        call find_closest(pdb_ref_coords,pdb_exp_coords,size(pdb_ref_coords,dim=2),size(pdb_exp_coords,dim=2),distances)
        print *, 'AVG DISTANCE = ', sum(distances)/size(distances)
    end subroutine compare_pick

    subroutine kill(self)
        class(nano_picker), intent(inout) :: self
        if (allocated(self%positions)) deallocate(self%positions)
        if (allocated(self%inds_offset)) deallocate(self%inds_offset)
        if (allocated(self%convolved_atoms)) deallocate(self%convolved_atoms)
        if (allocated(self%box_scores)) deallocate(self%box_scores)
    end subroutine kill

end module nano_detect_atoms
    
program simple_test_nano_detect_atoms
    include 'simple_lib.f08'
    use nano_detect_atoms
    use simple_nanoparticle
    use simple_image
    use simple_parameters

    type(nano_picker) :: test_sim, test_exp
    type(nanoparticle) :: nano
    real :: smpd, dist_thres
    character(len=2) :: element
    character(len=100) :: filename_exp, filename_sim, pdbfile_ref
    character(STDLEN) :: timestr
    type(image) :: simulated_NP
    integer :: offset, peak_thres_level, startTime, stopTime
    type(parameters), target :: params

    ! keeping track of how long program takes
    startTime= real(time())

    ! Inputs
    !filename_exp = 'recvol_state01_iter005.mrc' ! first draft of 3D reconstruction
    filename_exp = 'rec_merged.mrc'
    filename_sim = 'simulated_NP.mrc'
    !pdbfile_ref = 'ATMS.pdb'
    pdbfile_ref = 'rec_merged_ATMS.pdb'
    element = 'PT'
    smpd = 0.358
    offset = 2
    peak_thres_level = 2
    dist_thres = 3.
    
    ! simulate nanoparticle
    ! params_glob has to be set because of the way simple_nanoparticle is set up
    params_glob => params
    params_glob%element = element
    params_glob%smpd = smpd
    call nano%new(trim(filename_exp))
    call nano%set_atomic_coords(trim(pdbfile_ref))
    call nano%simulate_atoms(simatms=simulated_NP)
    call simulated_NP%write(trim(filename_sim))

    print *, 'SIMULATED DATA'
    !run picker workflow for simulated NP
    call test_sim%new(smpd, element, filename_sim, peak_thres_level)
    call test_sim%simulate_atom
    call test_sim%setup_iterators(offset)
    call test_sim%match_boxes
    call test_sim%identify_threshold
    !call test_sim%center_filter
    !call test_sim%distance_filter(dist_thres)
    !call test_sim%remove_outliers(2.5)
    call test_sim%cluster_filter(dist_thres)
    call test_sim%find_centers('simulated_centers')
    call test_sim%compare_pick(trim(pdbfile_ref),'simulated_centers.pdb')

    ! print *, ' '

    print *, 'EXPERIMENTAL DATA'
    ! run picker workflow for experimental data
    call test_exp%new(smpd, element, filename_exp, peak_thres_level)
    call test_exp%simulate_atom
    call test_exp%setup_iterators(offset)
    call test_exp%match_boxes
    call test_exp%identify_threshold
    !call test_exp%identify_threshold(0.155)
    !call test_exp%center_filter
    call test_exp%cluster_filter(dist_thres)
    !call test_exp%distance_filter(dist_thres)
    call test_exp%remove_outliers(3.)
    !call test_exp%cluster_filter(dist_thres)
    call test_exp%find_centers('experimental_centers')
    call test_exp%write_boximgs('exp_boximgs')
    call test_exp%compare_pick(trim(pdbfile_ref),'experimental_centers.pdb')

    stopTime = time()
    print *, 'RUNTIME = ', (stopTime - startTime), ' s'
    
end program simple_test_nano_detect_atoms
!-------------------------------------------------------------------------------
!
! MODULE: Delaporte
!
! AUTHOR: Avraham Adler <Avraham.Adler@gmail.com>
!
! DESCRIPTION: Probability mass, cumulative distribution, and quantile
!              functions for the Delaporte distribution. Random number
!              generation and method of moments functions as well.
!
! HISTORY:
!          Version 1.0: 2016-11-20
!                       Porting from C++ code in Delaporte package for R.
!          Version 1.1: 2017-03-01
!                       Various tweaks.
!          Version 1.2: 2017-08-13
!                       Corrected MoMdelap code.
!          Version 1.3: 2017-11-20
!                       Updates.
!          Version 1.4: 2018-06-18
!                       Added skew bias correction option to MoMdelap
!          Version 1.5: 2018-11-20
!                       Zapping absolute values <= EPS to 0
!          Version 1.6: 2018-12-10
!                       Replaced zapping with setting min to 0 and max to 1
!                       as appropriate. Less monkeying with values this way.
!          Version 2.0: 2021-01-03
!                       Setting limits as < 0 to be more consistent with R
!                       defaults for d/p/q/r functions. Returning NaN for NaN
!                       inputs per R defaults. Trapping for INFTY more
!                       consistently with base R. Should use ieee_arithmetic
!                       once current oldrelease gets deprecated and min GCC
!                       version is > 5. Using iso_fortran_env for INT64 to allow
!                       wider domain for d/pdelap
!
! LICENSE:
!   Copyright (c) 2016, Avraham Adler
!   All rights reserved.
!
!   Redistribution and use in source and binary forms, with or without
!   modification, are permitted provided that the following conditions are met:
!       1. Redistributions of source code must retain the above copyright
!          notice, this list of conditions and the following disclaimer.
!       2. Redistributions in binary form must reproduce the above copyright
!          notice, this list of conditions and the following disclaimer in the
!          documentation and/or other materials provided with the distribution.
!
!   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
!   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
!   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
!   ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
!   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
!   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
!   SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
!   INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
!   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
!   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
!   POSSIBILITY OF SUCH DAMAGE.
!-------------------------------------------------------------------------------

module delaporte
    use, intrinsic :: iso_c_binding
    use, intrinsic :: iso_fortran_env
    !$use omp_lib
    use utils
    use lgam

    implicit none
    private
    public :: ddelap_f, pdelap_f, qdelap_f, rdelap_f, momdelap_f

contains

!-------------------------------------------------------------------------------
! FUNCTION: ddelap_f_s
!
! DESCRIPTION: Calculate the Delaporte probability mass function for a single
!              observation and return the value or its log. Calculated through
!              explicit summation. Follows R convention that real observations
!              are errors and have 0 probability, so calls floor to build to
!              the last integer. Implements hard floor of 0 and hard ceiling of
!              1 to prevent spurious floating point errors.
!-------------------------------------------------------------------------------

    function ddelap_f_s(x, alpha, beta, lambda) result(pmf)

    external set_nan

    real(kind = c_double), intent(in)   :: x, alpha, beta, lambda
    real(kind = c_double)               :: pmf, ii, kk
    integer(INT64)                      :: i, k                   

        if (alpha <= ZERO .or. beta <= ZERO .or. lambda <= ZERO .or. x < ZERO &
            .or. alpha /= alpha .or. beta /= beta .or. lambda /= lambda &
            .or. x /= x) then
            call set_nan(pmf)
        else
            pmf = ZERO
            k = floor(x, INT64)
            kk = real(k, c_double)
            if (x < MAXD .and. x == kk) then
                do i = 0_INT64, k
                    ii = real(i, c_double)
                    pmf = pmf + exp(gamln(alpha + ii) + ii * log(beta) &
                    + (kk - ii) * log(lambda) - lambda - gamln(alpha) &
                    - gamln(ii + ONE) - (alpha + ii) * log1p(beta) &
                    - gamln(kk - ii + ONE))
                end do
            pmf = max(min(pmf, ONE), ZERO)        ! Clear floating point errors
            end if
        end if

    end function ddelap_f_s

!-------------------------------------------------------------------------------
! ROUTINE: ddelap_f
!
! DESCRIPTION: Vector-based PMF allowing parameter vector recycling and called 
!              from C. As Fortran starts its indices at 1, for the mod function
!              to properly recycle the vectors, the index needs to be reduced by
!              one, mod applied, and then increased by one again. Follows R
!              convention that real observations are errors and have 0
!              probability, so returns 0 for non-integer without calling
!              summation loop. 
!-------------------------------------------------------------------------------

    subroutine ddelap_f(x, nx, a, na, b, nb, l, nl, lg, pmfv) &
                        bind(C, name="ddelap_f_")
                        
    integer(kind = c_int), intent(in), value         :: nx, na, nb, nl
    real(kind = c_double), intent(in), dimension(nx) :: x
    real(kind = c_double), intent(out), dimension(nx):: pmfv
    real(kind = c_double), intent(in)                :: a(na), b(nb), l(nl)
    integer(kind = c_int), intent(in)                :: lg
    integer                                          :: i

        !$omp parallel do default(shared) private(i) schedule(static)
        do i = 1, nx
            pmfv(i) = ddelap_f_s(x(i), a(mod(i - 1, na) + 1), &
            b(mod(i - 1, nb) + 1), l(mod(i - 1, nl) + 1))
        end do
        !$omp end parallel do
        
        if (lg == 1) then
            pmfv = log(pmfv)
        end if
        
        if (any(pmfv /= pmfv)) then
            call rwarn("NaNs produced")
        end if
        
    end subroutine ddelap_f

!-------------------------------------------------------------------------------
! FUNCTION: pdelap_f_s
!
! DESCRIPTION: Calculate the Delaporte cumulative distribution function for a
!              single observation and return the value or its log. Calculated
!              through explicit summation. Follows R convention that real
!              observations are errors and have 0 probability, so calls floor to
!              build to last integer. Implements hard floor of 0 and hard
!              ceiling of 1 to prevent spurious floating point errors.
!-------------------------------------------------------------------------------

    function pdelap_f_s(q, alpha, beta, lambda) result(cdf)

    external set_nan

    real(kind = c_double)               :: cdf
    real(kind = c_double), intent(in)   :: q, alpha, beta, lambda
    integer(INT64)                      :: i, k

        if (alpha <= ZERO .or. beta <= ZERO .or. lambda <= ZERO .or. q < ZERO &
            .or. alpha /= alpha .or. beta /= beta .or. lambda /= lambda &
            .or. q /= q) then
            call set_nan(cdf)
        else if (q >= HUGE(q)) then
            cdf = ONE
        else
            k = floor(q, INT64)
            cdf = exp(-lambda) / ((beta + ONE) ** alpha)
            do i = 1_INT64, k
                cdf = cdf + ddelap_f_s(real(i, c_double), alpha, beta, lambda)
            end do
        cdf = max(min(cdf, ONE), ZERO)        ! Clear floating point errors
        end if

    end function pdelap_f_s

!-------------------------------------------------------------------------------
! ROUTINE: pdelap_f
!
! DESCRIPTION: Vector-based CDF allowing parameter vector recycling and called
!              from C. If parameters are all singletons (not vectors) then the
!              idea is to find the largest value in the vector and build the PDF
!              up to that point. Building the vector has each succesive value
!              piggyback off of the prior instead of calling p_delap_f_s each
!              time which increases the speed dramatically. Once created,
!              remaining values are simple lookups off of the singlevec vector.
!              Otherwise, each entry will need to build its own pmf value by
!              calling p_delap_f_s on each entry. Implements hard floor of 0 and
!              hard ceiling of 1 to prevent spurious floating point errors.
!-------------------------------------------------------------------------------

    subroutine pdelap_f(q, nq, a, na, b, nb, l, nl, lt, lg, pmfv) &
                        bind(C, name="pdelap_f_")
                        
    external set_nan                        

    integer(kind = c_int), intent(in), value         :: nq, na, nb, nl
    real(kind = c_double), intent(in), dimension(nq) :: q
    real(kind = c_double), intent(out), dimension(nq):: pmfv
    real(kind = c_double), intent(in)                :: a(na), b(nb), l(nl)
    integer(kind = c_int), intent(in)                :: lg, lt
    real(kind = c_double), allocatable, dimension(:) :: singlevec
    integer                                          :: i, k

! If there are any complications at all, don't use the fast version. pdelap_f_s
! and ddelap_f_s are more robust to improper entries

        if (na > 1 .or. nb > 1 .or. nl > 1 .or. minval(q) < ZERO .or. &
            maxval(q) > REAL(MAXVECSIZE, c_double) .or. any(q /= q)) then
            !$omp parallel do default(shared) private(i) schedule(static)
                do i = 1, nq
                    pmfv(i) = pdelap_f_s(q(i), a(mod(i - 1, na) + 1), &
                    b(mod(i - 1, nb) + 1), l(mod(i - 1, nl) + 1))
                end do
            !$omp end parallel do
        else
            if (a(1) <= ZERO .or. b(1) <= ZERO .or. l(1) <= ZERO .or. &
                a(1) /= a(1) .or. b(1) /= b(1) .or. l(1) /= l(1)) then
                do i = 1, nq
                    call set_nan(pmfv(i))
                end do
            else
                k = floor(maxval(q))
                allocate (singlevec(k + 1))
                singlevec(1) = exp(-l(1)) / ((b(1) + ONE) ** a(1))
                do i = 2, k + 1
                    singlevec(i) = singlevec(i - 1) &
                    + ddelap_f_s(real(i - 1, c_double), a(1), b(1), l(1))
                end do
                do i = 1, nq
                    k = floor(q(i))
                    pmfv(i) = singlevec(k + 1)
                end do
                deallocate(singlevec)
                pmfv = max(min(pmfv, ONE), ZERO) ! Clear floating point errors
            end if
        end if
        
        if (lt == 0) then
            pmfv = ONE - pmfv
        end if
        
        if (lg == 1) then
            pmfv = log(pmfv)
        end if
        
        if (any(pmfv /= pmfv)) then
            call rwarn("NaNs produced")
        end if
        
    end subroutine pdelap_f

!-------------------------------------------------------------------------------
! FUNCTION: qdelap_f_s
!
! DESCRIPTION: Calculate the Delaporte quantile function for a single 
!              observation and return the value. Calculated through explicit
!              summation. Returns NaN and Inf where appropriate.
!-------------------------------------------------------------------------------

    function qdelap_f_s(p, alpha, beta, lambda) result(value)

    external set_nan
    external set_inf

    real(kind = c_double), intent(in)   :: p, alpha, beta, lambda
    real(kind = c_double)               :: testcdf, value

        if (alpha <= ZERO .or. beta <= ZERO .or. lambda <= ZERO .or. p < ZERO &
          .or. alpha /= alpha .or. beta /= beta .or. lambda /= lambda &
          .or. p /= p) then
            call set_nan(value)
        else if (p >= ONE) then
            call set_inf(value)
        else
            value = ZERO
            testcdf = exp(-lambda) / ((beta + ONE) ** alpha)
            do while (p > testcdf)
                value = value + ONE
                testcdf = testcdf + ddelap_f_s(value, alpha, beta, lambda)
            end do
        end if

    end function qdelap_f_s

!-------------------------------------------------------------------------------
! ROUTINE: qdelap_f
!
! DESCRIPTION: Vector-based quantile function with parameter vector recycling.
!              If parameters are all singletons (not vectors) then the idea is
!              to find the largest value in the vector and build the PDF up to
!              that point. Building the vector has each succesive value
!              piggyback off of the prior instead of calling p_delap_f_s each
!              time which increases the speed dramatically. Once created,
!              remaining values are lookups off of the singlevec vector.
!              Otherwise, each entry will need to build its own pmf value by
!              calling q_delap_f_s on each entry.
!-------------------------------------------------------------------------------

    subroutine qdelap_f(p, np, a, na, b, nb, l, nl, lt, lg, obsv) &
                       bind(C, name="qdelap_f_")

    external set_nan
    external set_inf
    
    integer(kind = c_int), intent(in), value           :: np, na, nb, nl
    real(kind = c_double), intent(inout), dimension(np):: p
    real(kind = c_double), intent(out), dimension(np)  :: obsv
    real(kind = c_double), intent(in)                  :: a(na), b(nb), l(nl)
    integer(kind = c_int), intent(in)                  :: lg, lt
    real(kind = c_double), allocatable, dimension(:)   :: svec, tvec
    real(kind = c_double)                              :: x
    integer                                            :: i

        if (lg == 1) then
            p = exp(p)
        end if

        if (lt == 0) then
            p = ONE - p
        end if

        if(na == 1 .and. nb == na .and. nl == nb) then
            if (a(1) <= ZERO .or. b(1) <= ZERO .or. l(1) <= ZERO) then
                do i = 1, np
                    call set_nan(obsv(i))
                end do
            else
                x = maxval(p, 1, p < 1)
                i = 1
                allocate(svec(i))
                svec(1) = exp(-l(1)) / ((b(1) + ONE) ** a(1))
                do
                    if (svec(i) >= x) then
                        exit
                    end if
                    i = i + 1
                    allocate(tvec(1:i))
                    tvec(1:i-1) = svec
                    call move_alloc(tvec, svec)
                    svec(i) = svec(i - 1) + ddelap_f_s(real(i - 1, c_double), &
                                                       a(1), b(1), l(1))
                end do
                do i = 1, np
                    if (p(i) < ZERO .or. p(i) /= p(i)) then
                        call set_nan(obsv(i))
                    else if (p(i) >= ONE) then
                        call set_inf (obsv(i))
                    else
                        obsv(i) = real(position(p(i), svec) - 1)
                    end if
                end do
                deallocate(svec)
            end if
        else
            !$omp parallel do default(shared) private(i) schedule(static)
            do i = 1, np
                obsv(i) = qdelap_f_s(p(i), a(mod(i - 1, na) + 1), &
                                     b(mod(i - 1, nb) + 1), &
                                     l(mod(i - 1, nl) + 1))
            end do
            !$omp end parallel do
        end if
        
    end subroutine qdelap_f

!-------------------------------------------------------------------------------
! ROUTINE: rdelap_f
!
! DESCRIPTION: Vector-based random number generator with parameter vector
!              recycling. It calls a C procedure to generate uniform random
!              variates which jibe with R's own internals and then calls
!              qdelap_f on the uniforms. This allows qdelap's singleton mode to
!              activate if appropriate. This is the single routine slower in
!              this Fortran implementation than the prior C++ implementation, as
!              the vector creation and pushback is more efficient in C++ STL
!              than the ballet between allocate and move_alloc in Fortran. On
!              vector-valued parameters Fortran is faster than C++. Technically
!              this is a slowdown in qdelap, not rdelap, but the C++ version of
!              qdelap did not use the vector lookup trick; it was only
!              programmed in rdelap, wheras now the Fortran version of qdelap
!              uses the trick for a net speedup. Only rdelap suffers slightly.
!-------------------------------------------------------------------------------

    subroutine rdelap_f(n, a, na, b, nb, l, nl, vars) bind(C, name="rdelap_f_")

    external unifrnd

    integer(kind = c_int), intent(in), value           :: n, na, nb, nl
    real(kind = c_double), intent(out), dimension(n)   :: vars
    real(kind = c_double), intent(in)                  :: a(na), b(nb), l(nl)
    real(kind = c_double), dimension(n)                :: p
    integer(kind = c_int)                              :: lg, lt

        call unifrnd(n, p)
        lt = 1_c_int
        lg = 0_c_int
        call qdelap_f(p, n, a, na, b, nb, l, nl, lt, lg, vars)

    end subroutine rdelap_f

!-------------------------------------------------------------------------------
! ROUTINE: momdelap_f
!
! DESCRIPTION: Calculates method of moments estimates of parameters for a 
!              Delaporte distribution based on supplied vector. Based on
!              algorithms of Welford, Knuth, and Cook.
!              https://www.johndcook.com/blog/skewness_kurtosis/
!-------------------------------------------------------------------------------

    subroutine momdelap_f(obs, n, tp, params) bind(C, name="momdelap_f_")

    integer(kind = c_int), intent(in), value           :: n
    integer(kind = c_int), intent(in)                  :: tp
    real(kind = c_double), intent(in), dimension(n)    :: obs
    real(kind = c_double), intent(out), dimension(3)   :: params
    real(kind = c_double)                              :: nm1, P, Mu_D, M2, M3
    real(kind = c_double)                              :: T1, delta, delta_i, nr
    real(kind = c_double)                              :: Var_D, Skew_D, VmM_D
    real(kind = c_double)                              :: ii
    integer                                            :: i

        nr = real(n, c_double)
        nm1 = nr - ONE
        select case (tp)
            case (1)
                P = ONE
            case (2)
                P = sqrt(nr * nm1) / (nr - TWO)
            case (3)
                P = (nm1 / nr) ** THREEHALFS
            case default
                P = sqrt(nr * nm1) / (nr - TWO)
        end select
        Mu_D = ZERO
        M2 = ZERO
        M3 = ZERO
        do i = 1, n
            ii = real(i, c_double)
            delta = obs(i) - Mu_D
            delta_i = delta / ii
            T1 = delta * delta_i * (ii - ONE)
            Mu_D = Mu_D + delta_i
            M3 = M3 + (T1 * delta_i * (ii - TWO) - THREE * delta_i * M2)
            M2 = M2 + T1
        end do
        Var_D = M2 / nm1
        Skew_D = P * sqrt(nr) * M3 / (M2 ** THREEHALFS)
        VmM_D = Var_D - Mu_D
        params(2) = HALF * (Skew_D * (Var_D ** THREEHALFS) - Mu_D - THREE &
                            * VmM_D) / VmM_D
        params(1) = VmM_D / (params(2) ** 2)
        params(3) = Mu_D - params(1) * params(2)
 
    end subroutine momdelap_f

end module delaporte

{-# language FlexibleContexts #-}
module Lib where

import Control.Applicative

import Control.Monad.Primitive
-- import Control.Monad.State

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State.Strict (StateT, get, put, execStateT)
import Control.Monad.IO.Class (liftIO)

import System.Random.MWC.Probability

import Pipes (Producer, yield, (>->), await, runEffect)
import qualified Pipes.Prelude as P (take, mapM_, mapM)


newtype Transition m a = Trans { runTrans :: StateT a (Prob m) a}

stochVolatility1 :: PrimMonad m =>
   Double -> Double -> Double -> Double -> Transition m Double
stochVolatility1 a b sig alpha = Trans $ do
  x <- get
  ut <- lift $ normal 0 1
  vt <- lift $ alphaStableWD 0 alpha 1
  let xt = b * x + sig * ut
      yt = a * exp (xt / 2) * vt
  put yt
  return yt
    



sde0 :: Monad m => (b -> a -> b) -> Prob m a -> Transition m b
sde0 f mm = Trans $ do
  x <- get
  w <- lift mm
  let x' = f x w
  put x'
  return x'

chain :: Monad m => Transition m a -> a -> Gen (PrimState m) -> Producer a m ()
chain mm = loop where
  loop s g = do
    next <- lift $ sample (execStateT (runTrans mm) s) g
    yield next
    loop next g

runChain n t x0 g = runEffect $ chain t x0 g >-> P.take n >-> P.mapM_ print

-- -- `mcmc-types` introduces a Transition type: 
-- -- type Transition m a = StateT a (Prob m) ()

-- newtype Transition m a = Trans { runTrans :: StateT a (Prob m) () }

-- -- sde1 :: PrimMonad m => (Double -> Double) -> Transition m Double
-- sde1 f = Trans $ do
--   x <- get
--   w <- lift $ normal 0 1
--   let x' = f x + w
--   put x'


-- -- chain :: Monad m => Transition m t -> t -> Gen (PrimState m) -> Producer t m ()
-- chain mm = loop where
--   loop s g = do
--     next <- lift $ sample (execStateT (runTrans mm) s) g
--     yield next
--     loop next g

-- -- runChain :: Show b => Int -> Transition IO b -> b -> Gen RealWorld -> IO ()
-- runChain n t x0 g = runEffect $
--     chain t x0 g >->
--     P.take n
--     >-> await
--     -- >-> P.mapM return




-- * Levy-stable distribution
-- | 
genAlphaStable ::
  PrimMonad m => Double -> Double -> Int -> m [Double]
genAlphaStable al be n = do
  g <- create
  samples n (alphaStable al be) g

-- | The Chambers-Mallows-Stuck algorithm for producing a S_alpha(beta) stable r.v., using the continuous reparametrization around alpha=1
alphaStable :: PrimMonad m => Double -> Double -> Prob m Double
alphaStable al be = do
  u <- normal (-0.5 * pi) (0.5 * pi)  -- Phi
  w <- exponential 1
  let eps = 1 - al
      k = 1 - abs eps
      phi0 = - 0.5 * pi * be * k / al
      tap0 = tan (al * phi0)
      z = (cos (eps * u) - tap0 * sin (eps * u)) / (w * cos u)
      ze = z**(eps / al)
  return $ (sin(al*u)/cos u - tap0 * (cos (al * u) /cos u - 1))*ze + tap0*(1-ze)


-- | replaces all NaNs with a default value
alphaStableWD :: PrimMonad m => Double -> Double -> Double -> Prob m Double
alphaStableWD defv al be = whenNaN defv <$> alphaStable al be




-- ** Utilities

-- | Replace NaN with a default value
whenNaN :: RealFloat a => a -> a -> a
whenNaN val x
  | isNaN x   = val
  | otherwise = x


-- Not functional :

-- -- | The Chambers-Mallows-Stuck algorithm for producing a S_alpha(beta, c, mu) stable r.v., as reported in https://en.wikipedia.org/wiki/Stable_distribution#Simulation_of_stable_variables
-- alphaStable :: PrimMonad m => Double -> Double -> Double -> Double -> Prob m Double
-- alphaStable al be c mu = do
--   u <- normal (-0.5 * pi) (0.5 * pi)
--   w <- exponential 1
--   let zeta = be*tan(pi*al/2)
--   return $ case al of 1 ->
--                         let xi = pi/2
--                             s = pi/2 + be*u
--                             x = 1/xi*(s*tan u - be*log((pi/2*w*cos u)/s))
--                         in c*x + mu + (2/pi)*be*c*log c
--                       _ ->
--                         let xi = 1/al*atan(-zeta)
--                             t = u + xi
--                             t1 = (1 + zeta**2)**(1/(2*al))
--                             t2 = sin (al * t) / cos u**(1/al)
--                             t3 = (cos(u - al*t)/w)**((1-al)/al)
--                             x = t1 * t2 * t3
--                         in c*x + mu

-- Impulse Tracker (.IT) player in MATA-LL
-- Decodes IT modules to raw 16-bit stereo PCM via callback
-- Uses ST monad with STArray for O(1) channel state access

bsSetByte :: ByteString -> Integer -> Integer -> ByteString
bsSetByte bs idx val = bsConcat (bsSub bs 0 idx) (bsConcat (bsSingleton val) (bsSub bs (idx + 1) (bsLength bs - idx - 1)))

outRate :: Integer
outRate = 44100

clamp :: Integer -> Integer -> Integer -> Integer
clamp lo hi x = if x < lo then lo else if x > hi then hi else x

nth :: [Integer] -> Integer -> Integer
nth (x:_) 0 = x
nth (_:xs) n = nth xs (n - 1)
nth [] _ = 0

lset :: [Integer] -> Integer -> Integer -> [Integer]
lset [] _ _ = []
lset (_:xs) 0 v = v : xs
lset (x:xs) n v = x : lset xs (n - 1) v

appI :: [Integer] -> [Integer] -> [Integer]
appI [] ys = ys
appI (x:xs) ys = x : appI xs ys

-- ========== Header ==========

hdrOrdNum :: ByteString -> Integer
hdrOrdNum bs = bsGetU16LE bs 32

hdrSmpNum :: ByteString -> Integer
hdrSmpNum bs = bsGetU16LE bs 36

hdrPatNum :: ByteString -> Integer
hdrPatNum bs = bsGetU16LE bs 38

hdrSpeed :: ByteString -> Integer
hdrSpeed bs = bsIndex bs 50

hdrTempo :: ByteString -> Integer
hdrTempo bs = bsIndex bs 51

getOrder :: ByteString -> Integer -> Integer
getOrder bs i = bsIndex bs (192 + i)

getChanPan :: ByteString -> Integer -> Integer
getChanPan bs ch = bsIndex bs (64 + ch)

-- ========== Sample Headers ==========

smpOffset :: ByteString -> Integer -> Integer
smpOffset bs i = bsGetU32LE bs (192 + hdrOrdNum bs + i * 4)

smpLen :: ByteString -> Integer -> Integer
smpLen bs off = bsGetU32LE bs (off + 48)

smpLoopBegin :: ByteString -> Integer -> Integer
smpLoopBegin bs off = bsGetU32LE bs (off + 52)

smpLoopEnd :: ByteString -> Integer -> Integer
smpLoopEnd bs off = bsGetU32LE bs (off + 56)

smpC5Freq :: ByteString -> Integer -> Integer
smpC5Freq bs off = bsGetU32LE bs (off + 60)

smpDataPtr :: ByteString -> Integer -> Integer
smpDataPtr bs off = bsGetU32LE bs (off + 72)

smpDefaultVol :: ByteString -> Integer -> Integer
smpDefaultVol bs off = bsIndex bs (off + 19)

smpFlags :: ByteString -> Integer -> Integer
smpFlags bs off = bsIndex bs (off + 18)

smpIs16Bit :: Integer -> Bool
smpIs16Bit flags = (flags `div` 2) `mod` 2 == 1

smpHasLoop :: Integer -> Bool
smpHasLoop flags = (flags `div` 16) `mod` 2 == 1

-- Read sample value: 16-bit signed (little-endian) or 8-bit signed
readSmp :: ByteString -> Integer -> Integer -> Bool -> Integer
readSmp bs dPtr pos is16 = if is16 then bsGetI16LE bs (dPtr + pos * 2) else let v = bsIndex bs (dPtr + pos) in if v >= 128 then v - 256 else v

-- ========== Pattern Headers ==========

patOffset :: ByteString -> Integer -> Integer
patOffset bs i = bsGetU32LE bs (192 + hdrOrdNum bs + hdrSmpNum bs * 4 + i * 4)

patRows :: ByteString -> Integer -> Integer
patRows bs off = bsGetU16LE bs (off + 2)

-- ========== Note Frequency ==========

semiRatio :: Integer -> Integer
semiRatio 0 = 65536
semiRatio 1 = 69433
semiRatio 2 = 73562
semiRatio 3 = 77936
semiRatio 4 = 82570
semiRatio 5 = 87480
semiRatio 6 = 92682
semiRatio 7 = 98193
semiRatio 8 = 104032
semiRatio 9 = 110218
semiRatio 10 = 116772
semiRatio 11 = 123715
semiRatio _ = 65536

pow2 :: Integer -> Integer
pow2 0 = 1
pow2 n = 2 * pow2 (n - 1)

-- Returns increment in 8.8 fixed-point (256 = advance 1 sample per frame)
noteInc :: Integer -> Integer -> Integer
noteInc note c5 = let oct = (note `div` 12) - 5 in let semi = note `mod` 12 in let base = (c5 * semiRatio semi * 256) `div` (outRate * 65536) in if oct >= 0 then base * pow2 oct else base `div` pow2 (0 - oct)

-- ========== Channel State (STArray) ==========
-- 14 fields per channel: smp, posH, posL, incH, incL, vol, pan, act, len, lpS, lpE, lp, dPtr, c5

nf :: Integer
nf = 14

fi :: Integer -> Integer -> Integer
fi ch f = ch * nf + f

-- Field indices
fiSmp :: Integer
fiSmp = 0
fiPos :: Integer
fiPos = 1
fi16 :: Integer
fi16 = 2
fiInc :: Integer
fiInc = 3
fiVol :: Integer
fiVol = 5
fiPan :: Integer
fiPan = 6
fiAct :: Integer
fiAct = 7
fiLen :: Integer
fiLen = 8
fiLpS :: Integer
fiLpS = 9
fiLpE :: Integer
fiLpE = 10
fiLp :: Integer
fiLp = 11
fiDPtr :: Integer
fiDPtr = 12
fiC5 :: Integer
fiC5 = 13

-- Init channel state as a flat list (for transfer between ticks)
mkChan :: Integer -> [Integer]
mkChan pan = [0, 0, 0, 0, 0, 0, pan, 0, 0, 0, 0, 0, 0, 8363]

initChans :: ByteString -> Integer -> Integer -> [Integer]
initChans fd n i = if i >= n then [] else let p = getChanPan fd i in let pv = if p >= 128 then 32 else p in appI (mkChan pv) (initChans fd n (i + 1))

-- ========== Pattern Decoding (pure, on [Integer] state) ==========

decodeRow :: ByteString -> Integer -> [Integer] -> ByteString -> Integer -> Integer -> ([Integer], (ByteString, Integer))
decodeRow fd off st masks numCh numSmp = decRowLoop fd off st masks numCh numSmp

decRowLoop :: ByteString -> Integer -> [Integer] -> ByteString -> Integer -> Integer -> ([Integer], (ByteString, Integer))
decRowLoop fd off st masks numCh numSmp = let marker = bsIndex fd off in if marker == 0 then (st, (masks, off + 1)) else let ch = (marker - 1) `mod` 64 in let hasMaskBit = marker `div` 128 in let off2 = off + 1 in let mask = if hasMaskBit == 1 then bsIndex fd off2 else bsIndex masks ch in let masks2 = if hasMaskBit == 1 then bsSetByte masks ch mask else masks in let off3 = if hasMaskBit == 1 then off2 + 1 else off2 in let hasNote = mask `mod` 2 in let hasIns = (mask `div` 2) `mod` 2 in let hasVol = (mask `div` 4) `mod` 2 in let hasCmd = (mask `div` 8) `mod` 2 in let note = if hasNote == 1 then bsIndex fd off3 else 255 in let off4 = off3 + hasNote in let ins = if hasIns == 1 then bsIndex fd off4 else 0 in let off5 = off4 + hasIns in let vol = if hasVol == 1 then bsIndex fd off5 else 255 in let off6 = off5 + hasVol in let off7 = off6 + (if hasCmd == 1 then 2 else 0) in let st2 = trigNote fd st ch note ins vol numSmp in decRowLoop fd off7 st2 masks2 numCh numSmp

trigNote :: ByteString -> [Integer] -> Integer -> Integer -> Integer -> Integer -> Integer -> [Integer]
trigNote fd st ch note ins vol numSmp = if note == 254 then lset st (fi ch fiAct) 0 else let st2 = if ins > 0 && ins <= numSmp then loadSmp fd st ch ins else st in let st3 = if note < 120 then setNoteFreq st2 ch note else st2 in let st4 = if note < 120 then lset st3 (fi ch fiAct) 1 else st3 in if vol <= 64 then lset st4 (fi ch fiVol) vol else st4

setNoteFreq :: [Integer] -> Integer -> Integer -> [Integer]
setNoteFreq st ch note = let c5 = nth st (fi ch fiC5) in let inc = noteInc note c5 in lset (lset (lset st (fi ch fiPos) 0) (fi ch fiInc) inc) (fi ch fiAct) 1

loadSmp :: ByteString -> [Integer] -> Integer -> Integer -> [Integer]
loadSmp fd st ch sn = let off = smpOffset fd (sn - 1) in let sl = smpLen fd off in let lb = smpLoopBegin fd off in let le = smpLoopEnd fd off in let c5 = smpC5Freq fd off in let dp = smpDataPtr fd off in let dv = smpDefaultVol fd off in let fl = smpFlags fd off in let hl = if smpHasLoop fl then 1 else 0 in let b16 = if smpIs16Bit fl then 1 else 0 in lset (lset (lset (lset (lset (lset (lset (lset (lset st (fi ch fiSmp) sn) (fi ch fiLen) sl) (fi ch fiLpS) lb) (fi ch fiLpE) le) (fi ch fiLp) hl) (fi ch fiDPtr) dp) (fi ch fiC5) c5) (fi ch fiVol) dv) (fi ch fi16) b16

-- ========== Mixing (ST monad for O(1) array access) ==========

-- Mix one tick: takes channel state list, returns (pcm, new state list)
mixTick :: ByteString -> [Integer] -> Integer -> Integer -> (ByteString, [Integer])
mixTick fd st spt numCh = runST (do
    arr <- newSTArrayFromList st
    pcm <- mixFrames fd arr spt numCh bsEmpty
    st2 <- stArrayToList arr
    return (pcm, st2))

mixFrames :: ByteString -> STArray s -> Integer -> Integer -> ByteString -> ST s ByteString
mixFrames fd arr 0 _ acc = return acc
mixFrames fd arr n numCh acc = do
    frame <- mixFrame fd arr numCh 0 0 0
    let l = fst frame
    let r = snd frame
    let pcm = bsConcat (bsPutI16LE (clamp (0 - 32768) 32767 l)) (bsPutI16LE (clamp (0 - 32768) 32767 r))
    mixFrames fd arr (n - 1) numCh (bsConcat acc pcm)

mixFrame :: ByteString -> STArray s -> Integer -> Integer -> Integer -> Integer -> ST s (Integer, Integer)
mixFrame fd arr numCh ch la ra = if ch >= numCh then return (la, ra) else do
    act <- readSTArray arr (fi ch fiAct)
    if act == 0 then mixFrame fd arr numCh (ch + 1) la ra else do
        pos <- readSTArray arr (fi ch fiPos)
        sl <- readSTArray arr (fi ch fiLen)
        dp <- readSTArray arr (fi ch fiDPtr)
        vol <- readSTArray arr (fi ch fiVol)
        pan <- readSTArray arr (fi ch fiPan)
        is16 <- readSTArray arr (fi ch fi16)
        let smpPos = pos `div` 256
        let smp = if smpPos < sl then readSmp fd dp smpPos (is16 == 1) else 0
        let scaled = if is16 == 1 then smp `div` 256 else smp
        let sv = scaled * vol * 4
        let nl = la + (sv * (64 - pan)) `div` 64
        let nr = ra + (sv * pan) `div` 64
        advPos arr ch
        mixFrame fd arr numCh (ch + 1) nl nr

advPos :: STArray s -> Integer -> ST s ()
advPos arr ch = do
    pos <- readSTArray arr (fi ch fiPos)
    inc <- readSTArray arr (fi ch fiInc)
    sl <- readSTArray arr (fi ch fiLen)
    hl <- readSTArray arr (fi ch fiLp)
    ls <- readSTArray arr (fi ch fiLpS)
    le <- readSTArray arr (fi ch fiLpE)
    let nPos = pos + inc
    let slFP = sl * 256
    let lsFP = ls * 256
    let leFP = le * 256
    let fPos = if hl == 1 && nPos >= leFP && leFP > lsFP then lsFP + ((nPos - lsFP) `mod` (leFP - lsFP)) else nPos
    writeSTArray arr (fi ch fiPos) fPos
    if hl == 0 && nPos >= slFP then writeSTArray arr (fi ch fiAct) 0 else return ()

-- ========== Playback Loop (LuaIO for output callback) ==========

doTicks :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer] -> Integer -> Integer -> Integer -> Integer -> LuaIO s [Integer]
doTicks fd sw st speed spt numCh tick = if tick >= speed then return st else let tr = mixTick fd st spt numCh in let pcm = fst tr in let st2 = snd tr in sw pcm >> doTicks fd sw st2 speed spt numCh (tick + 1)

doRows :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer] -> ByteString -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> LuaIO s [Integer]
doRows fd sw st masks dataOff row numRows speed tempo numCh numSmp = if row >= numRows then return st else let rr = decodeRow fd dataOff st masks numCh numSmp in let st2 = fst rr in let masks2 = fst (snd rr) in let nextOff = snd (snd rr) in let spt = (outRate * 60) `div` (tempo * 24) in doTicks fd sw st2 speed spt numCh 0 >>= (\st3 -> doRows fd sw st3 masks2 nextOff (row + 1) numRows speed tempo numCh numSmp)

doOrders :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer] -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> LuaIO s ()
doOrders fd sw st idx ordNum speed tempo numCh numSmp = if idx >= ordNum then return () else let pat = getOrder fd idx in if pat >= 254 then return () else let pOff = patOffset fd pat in let nRows = patRows fd pOff in let masks = bsReplicate 64 0 in doRows fd sw st masks (pOff + 8) 0 nRows speed tempo numCh numSmp >>= (\st2 -> doOrders fd sw st2 (idx + 1) ordNum speed tempo numCh numSmp)

export play :: (ByteString -> LuaIO s ()) -> ByteString -> LuaIO s ()
play swallower fd = let numCh = 22 in let st = initChans fd numCh 0 in doOrders fd swallower st 0 (hdrOrdNum fd) (hdrSpeed fd) (hdrTempo fd) numCh (hdrSmpNum fd)

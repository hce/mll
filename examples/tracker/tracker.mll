-- Impulse Tracker (.IT) player in MATA-LL
-- Decodes IT modules to raw 16-bit stereo PCM via callback

-- Set byte at 0-based index in ByteString
bsSetByte :: ByteString -> Integer -> Integer -> ByteString
bsSetByte bs idx val = bsConcat (bsSub bs 0 idx) (bsConcat (bsSingleton val) (bsSub bs (idx + 1) (bsLength bs - idx - 1)))

outRate :: Integer
outRate = 44100

clamp :: Integer -> Integer -> Integer -> Integer
clamp lo hi x = if x < lo then lo else if x > hi then hi else x

-- List append (monomorphic to avoid monomorphizer issues)
appI :: [Integer] -> [Integer] -> [Integer]
appI [] ys = ys
appI (x:xs) ys = x : appI xs ys

-- List indexing
nth :: [Integer] -> Integer -> Integer
nth (x:_) 0 = x
nth (_:xs) n = nth xs (n - 1)
nth [] _ = 0

-- List set
lset :: [Integer] -> Integer -> Integer -> [Integer]
lset [] _ _ = []
lset (_:xs) 0 v = v : xs
lset (x:xs) n v = x : lset xs (n - 1) v

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

hdrGlobalVol :: ByteString -> Integer
hdrGlobalVol bs = bsIndex bs 48

hdrMixVol :: ByteString -> Integer
hdrMixVol bs = bsIndex bs 49

getOrder :: ByteString -> Integer -> Integer
getOrder bs i = bsIndex bs (192 + i)

getChanPan :: ByteString -> Integer -> Integer
getChanPan bs ch = bsIndex bs (64 + ch)

getChanVol :: ByteString -> Integer -> Integer
getChanVol bs ch = bsIndex bs (128 + ch)

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
smpDefaultVol bs off = bsIndex bs (off + 18)

smpFlags :: ByteString -> Integer -> Integer
smpFlags bs off = bsIndex bs (off + 17)

smpHasLoop :: Integer -> Bool
smpHasLoop flags = (flags `div` 16) `mod` 2 == 1

readSmp8 :: ByteString -> Integer -> Integer -> Integer
readSmp8 bs dPtr pos = let v = bsIndex bs (dPtr + pos) in if v >= 128 then v - 256 else v

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

noteInc :: Integer -> Integer -> Integer
noteInc note c5 = let oct = (note `div` 12) - 5 in let semi = note `mod` 12 in let base = (c5 * semiRatio semi) `div` outRate in if oct >= 0 then (base * pow2 oct) `div` 65536 else base `div` (pow2 (0 - oct) * 65536)

-- ========== Channel State ==========
-- 14 fields per channel packed in a flat list

numFields :: Integer
numFields = 14

chGet :: [Integer] -> Integer -> Integer -> Integer
chGet st ch f = nth st (ch * numFields + f)

chSet :: [Integer] -> Integer -> Integer -> Integer -> [Integer]
chSet st ch f v = lset st (ch * numFields + f) v

-- Field indices
fiSmp :: Integer
fiSmp = 0
fiPosH :: Integer
fiPosH = 1
fiPosL :: Integer
fiPosL = 2
fiIncH :: Integer
fiIncH = 3
fiIncL :: Integer
fiIncL = 4
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

mkChan :: Integer -> [Integer]
mkChan pan = [0, 0, 0, 0, 0, 0, pan, 0, 0, 0, 0, 0, 0, 8363]

initChans :: ByteString -> Integer -> Integer -> [Integer]
initChans fd n i = if i >= n then [] else let p = getChanPan fd i in let pv = if p >= 128 then 32 else p in appI (mkChan pv) (initChans fd n (i + 1))

-- ========== Pattern Decoding ==========

-- Per-channel mask storage: ByteString of 64 bytes
-- Process one row: returns (newState, (newMasks, newDataOffset))
decodeRow :: ByteString -> Integer -> [Integer] -> ByteString -> Integer -> Integer -> ([Integer], (ByteString, Integer))
decodeRow fd off st masks numCh numSmp = decRowLoop fd off st masks numCh numSmp

decRowLoop :: ByteString -> Integer -> [Integer] -> ByteString -> Integer -> Integer -> ([Integer], (ByteString, Integer))
decRowLoop fd off st masks numCh numSmp = let marker = bsIndex fd off in if marker == 0 then (st, (masks, off + 1)) else let ch = (marker - 1) `mod` 64 in let hasMaskBit = marker `div` 128 in let off2 = off + 1 in let mask = if hasMaskBit == 1 then bsIndex fd off2 else bsIndex masks ch in let masks2 = if hasMaskBit == 1 then bsSetByte masks ch mask else masks in let off3 = if hasMaskBit == 1 then off2 + 1 else off2 in let hasNote = mask `mod` 2 in let hasIns = (mask `div` 2) `mod` 2 in let hasVol = (mask `div` 4) `mod` 2 in let hasCmd = (mask `div` 8) `mod` 2 in let note = if hasNote == 1 then bsIndex fd off3 else 255 in let off4 = off3 + hasNote in let ins = if hasIns == 1 then bsIndex fd off4 else 0 in let off5 = off4 + hasIns in let vol = if hasVol == 1 then bsIndex fd off5 else 255 in let off6 = off5 + hasVol in let cmd = if hasCmd == 1 then bsIndex fd off6 else 0 in let cmdVal = if hasCmd == 1 then bsIndex fd (off6 + 1) else 0 in let off7 = off6 + (if hasCmd == 1 then 2 else 0) in let st2 = trigNote fd st ch note ins vol numSmp in decRowLoop fd off7 st2 masks2 numCh numSmp

-- Trigger note on channel
trigNote :: ByteString -> [Integer] -> Integer -> Integer -> Integer -> Integer -> Integer -> [Integer]
trigNote fd st ch note ins vol numSmp = if note == 254 then chSet st ch fiAct 0 else let st2 = if ins > 0 && ins <= numSmp then loadSmp fd st ch ins else st in let st3 = if note < 120 then setNoteFreq st2 ch note else st2 in let st4 = if note < 120 then chSet st3 ch fiAct 1 else st3 in if vol <= 64 then chSet st4 ch fiVol vol else st4

setNoteFreq :: [Integer] -> Integer -> Integer -> [Integer]
setNoteFreq st ch note = let c5 = chGet st ch fiC5 in let inc = noteInc note c5 in chSet (chSet (chSet (chSet st ch fiPosH 0) ch fiPosL 0) ch fiIncH inc) ch fiIncL 0

loadSmp :: ByteString -> [Integer] -> Integer -> Integer -> [Integer]
loadSmp fd st ch sn = let off = smpOffset fd (sn - 1) in let sl = smpLen fd off in let lb = smpLoopBegin fd off in let le = smpLoopEnd fd off in let c5 = smpC5Freq fd off in let dp = smpDataPtr fd off in let dv = smpDefaultVol fd off in let fl = smpFlags fd off in let hl = if smpHasLoop fl then 1 else 0 in chSet (chSet (chSet (chSet (chSet (chSet (chSet (chSet st ch fiSmp sn) ch fiLen sl) ch fiLpS lb) ch fiLpE le) ch fiLp hl) ch fiDPtr dp) ch fiC5 c5) ch fiVol dv

-- ========== Mixing ==========

mixTick :: ByteString -> [Integer] -> Integer -> Integer -> (ByteString, [Integer])
mixTick fd st spt numCh = mixFrames fd st spt numCh bsEmpty

mixFrames :: ByteString -> [Integer] -> Integer -> Integer -> ByteString -> (ByteString, [Integer])
mixFrames fd st 0 _ acc = (acc, st)
mixFrames fd st n numCh acc = let fr = mixFrame fd st numCh 0 0 0 in let l = fst (fst fr) in let r = snd (fst fr) in let st2 = snd fr in let pcm = bsConcat (bsPutI16LE (clamp (0 - 32768) 32767 l)) (bsPutI16LE (clamp (0 - 32768) 32767 r)) in mixFrames fd st2 (n - 1) numCh (bsConcat acc pcm)

mixFrame :: ByteString -> [Integer] -> Integer -> Integer -> Integer -> Integer -> ((Integer, Integer), [Integer])
mixFrame fd st numCh ch la ra = if ch >= numCh then ((la, ra), st) else if chGet st ch fiAct == 0 then mixFrame fd st numCh (ch + 1) la ra else let pos = chGet st ch fiPosH in let sl = chGet st ch fiLen in let dp = chGet st ch fiDPtr in let vol = chGet st ch fiVol in let pan = chGet st ch fiPan in let smp = if pos < sl then readSmp8 fd dp pos else 0 in let sv = smp * vol * 4 in let nl = la + (sv * (64 - pan)) `div` 64 in let nr = ra + (sv * pan) `div` 64 in let st2 = advPos st ch in mixFrame fd st2 numCh (ch + 1) nl nr

advPos :: [Integer] -> Integer -> [Integer]
advPos st ch = let pos = chGet st ch fiPosH in let inc = chGet st ch fiIncH in let nPos = pos + inc in let sl = chGet st ch fiLen in let hl = chGet st ch fiLp in let ls = chGet st ch fiLpS in let le = chGet st ch fiLpE in let fPos = if hl == 1 && nPos >= le && le > ls then ls + ((nPos - ls) `mod` (le - ls)) else nPos in let act = if hl == 0 && fPos >= sl then 0 else 1 in chSet (chSet st ch fiPosH fPos) ch fiAct act

-- ========== Playback Loop ==========

-- Process ticks for one row
doTicks :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer] -> Integer -> Integer -> Integer -> Integer -> LuaIO s [Integer]
doTicks fd sw st speed spt numCh tick = if tick >= speed then return st else let tr = mixTick fd st spt numCh in let pcm = fst tr in let st2 = snd tr in sw pcm >> doTicks fd sw st2 speed spt numCh (tick + 1)

-- Process all rows in a pattern
doRows :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer] -> ByteString -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> LuaIO s [Integer]
doRows fd sw st masks dataOff row numRows speed tempo numCh numSmp = if row >= numRows then return st else let rr = decodeRow fd dataOff st masks numCh numSmp in let st2 = fst rr in let masks2 = fst (snd rr) in let nextOff = snd (snd rr) in let spt = (outRate * 60) `div` (tempo * 24) in doTicks fd sw st2 speed spt numCh 0 >>= (\st3 -> doRows fd sw st3 masks2 nextOff (row + 1) numRows speed tempo numCh numSmp)

-- Process all orders
doOrders :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer] -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> LuaIO s ()
doOrders fd sw st idx ordNum speed tempo numCh numSmp = if idx >= ordNum then return () else let pat = getOrder fd idx in if pat >= 254 then return () else let pOff = patOffset fd pat in let nRows = patRows fd pOff in let masks = bsReplicate 64 0 in doRows fd sw st masks (pOff + 8) 0 nRows speed tempo numCh numSmp >>= (\st2 -> doOrders fd sw st2 (idx + 1) ordNum speed tempo numCh numSmp)

export play :: (ByteString -> LuaIO s ()) -> ByteString -> LuaIO s ()
play swallower fd = let numCh = 22 in let st = initChans fd numCh 0 in doOrders fd swallower st 0 (hdrOrdNum fd) (hdrSpeed fd) (hdrTempo fd) numCh (hdrSmpNum fd)

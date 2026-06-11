-- Impulse Tracker (.IT) player in MATA-LL
-- Decodes IT modules to raw 16-bit stereo PCM via callback
-- All channel state lives in a single STArray across decode + mix

bsSetByte :: ByteString -> Integer -> Integer -> ByteString
bsSetByte bs idx val = bsConcat (bsSub bs 0 idx) (bsConcat (bsSingleton val) (bsSub bs (idx + 1) (bsLength bs - idx - 1)))

outRate :: Integer
outRate = 44100

clamp :: Integer -> Integer -> Integer -> Integer
clamp lo hi x =
    if x < lo then lo
    else if x > hi then hi
    else x

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

countActiveChans :: ByteString -> Integer -> Integer -> Integer
countActiveChans bs n i =
    if i >= 64 then n
    else if getChanPan bs i < 128
    then countActiveChans bs (n + 1) (i + 1)
    else countActiveChans bs n (i + 1)

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

smpGlobalVol :: ByteString -> Integer -> Integer
smpGlobalVol bs off = bsIndex bs (off + 17)

smpDefaultVol :: ByteString -> Integer -> Integer
smpDefaultVol bs off = bsIndex bs (off + 19)

smpFlags :: ByteString -> Integer -> Integer
smpFlags bs off = bsIndex bs (off + 18)

smpIs16Bit :: Integer -> Bool
smpIs16Bit flags = (flags `div` 2) `mod` 2 == 1

smpHasLoop :: Integer -> Bool
smpHasLoop flags = (flags `div` 16) `mod` 2 == 1

readSmp :: ByteString -> Integer -> Integer -> Bool -> Integer
readSmp bs dPtr pos is16 =
    if is16
    then bsGetI16LE bs (dPtr + pos * 2)
    else let v = bsIndex bs (dPtr + pos)
         in if v >= 128 then v - 256 else v

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
noteInc note c5 =
    let oct  = (note `div` 12) - 5
        semi = note `mod` 12
        base = (c5 * semiRatio semi * 256) `div` (outRate * 65536)
    in if oct >= 0
       then base * pow2 oct
       else base `div` pow2 (0 - oct)

-- ========== Channel State (STArray) ==========
-- 14 fields per channel packed in a flat array

nf :: Integer
nf = 14

fi :: Integer -> Integer -> Integer
fi ch f = ch * nf + f

fiSmp :: Integer
fiSmp = 0
fiPos :: Integer
fiPos = 1
fi16 :: Integer
fi16 = 2
fiInc :: Integer
fiInc = 3
fiGVl :: Integer
fiGVl = 4
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
initChans fd n i =
    if i >= n
    then []
    else let p  = getChanPan fd i
             pv = if p >= 128 then 32 else p
         in appI (mkChan pv) (initChans fd n (i + 1))

-- ========== Pattern Decoding (ST monad — O(1) array access) ==========

decodeRow :: ByteString -> Integer -> STArray s -> ByteString
    -> ByteString -> Integer -> Integer
    -> ST s (ByteString, (ByteString, Integer))
decodeRow fd off arr masks lv numCh numSmp =
    decRowLoop fd off arr masks lv numCh numSmp

decRowLoop :: ByteString -> Integer -> STArray s -> ByteString
    -> ByteString -> Integer -> Integer
    -> ST s (ByteString, (ByteString, Integer))
decRowLoop fd off arr masks lv numCh numSmp =
    let marker = bsIndex fd off
    in if marker == 0
       then return (masks, (lv, off + 1))
       else let ch   = (marker - 1) `mod` 64
                hmb  = marker `div` 128
                off2 = off + 1
                mask = if hmb == 1 then bsIndex fd off2 else bsIndex masks ch
                msk2 = if hmb == 1 then bsSetByte masks ch mask else masks
                off3 = if hmb == 1 then off2 + 1 else off2
                b0 = mask `mod` 2
                b1 = (mask `div` 2) `mod` 2
                b2 = (mask `div` 4) `mod` 2
                b3 = (mask `div` 8) `mod` 2
                b4 = (mask `div` 16) `mod` 2
                b5 = (mask `div` 32) `mod` 2
                b6 = (mask `div` 64) `mod` 2
                note = if b0 == 1 then bsIndex fd off3 else if b4 == 1 then bsIndex lv (ch * 4) else 255
                off4 = off3 + b0
                ins  = if b1 == 1 then bsIndex fd off4 else if b5 == 1 then bsIndex lv (ch * 4 + 1) else 0
                off5 = off4 + b1
                vol  = if b2 == 1 then bsIndex fd off5 else if b6 == 1 then bsIndex lv (ch * 4 + 2) else 255
                off6 = off5 + b2
                cmd    = if b3 == 1 then bsIndex fd off6 else 0
                cmdVal = if b3 == 1 then bsIndex fd (off6 + 1) else 0
                off7 = off6 + (if b3 == 1 then 2 else 0)
                lv2 = if b0 == 1 then bsSetByte lv  (ch * 4)     note else lv
                lv3 = if b1 == 1 then bsSetByte lv2 (ch * 4 + 1) ins  else lv2
                lv4 = if b2 == 1 then bsSetByte lv3 (ch * 4 + 2) vol  else lv3
            in trigNote fd arr ch note ins vol cmd cmdVal numSmp
                >> decRowLoop fd off7 arr msk2 lv4 numCh numSmp

trigNote :: ByteString -> STArray s -> Integer -> Integer
    -> Integer -> Integer -> Integer -> Integer
    -> Integer -> ST s ()
trigNote fd arr ch note ins vol cmd cmdVal numSmp =
    if note == 254
    then writeSTArray arr (fi ch fiAct) 0
    else do
        if ins > 0 && ins <= numSmp then loadSmp fd arr ch ins else return ()
        if note < 120 then setNoteFreq arr ch note else return ()
        applyVol arr ch vol
        applyEffect arr ch cmd cmdVal

applyVol :: STArray s -> Integer -> Integer -> ST s ()
applyVol arr ch vol =
    if vol <= 64 then writeSTArray arr (fi ch fiVol) vol
    else if vol >= 128 && vol <= 192 then writeSTArray arr (fi ch fiPan) (vol - 128)
    else return ()

applyEffect :: STArray s -> Integer -> Integer -> Integer -> ST s ()
applyEffect arr ch cmd val =
    if cmd == 8
    then writeSTArray arr (fi ch fiPan) (val `div` 4)
    else if cmd == 19 && (val `div` 16) == 8
    then writeSTArray arr (fi ch fiPan) (((val `mod` 16) * 17) `div` 4)
    else return ()

setNoteFreq :: STArray s -> Integer -> Integer -> ST s ()
setNoteFreq arr ch note = do
    c5 <- readSTArray arr (fi ch fiC5)
    let inc = noteInc note c5
    writeSTArray arr (fi ch fiPos) 0
    writeSTArray arr (fi ch fiInc) inc
    writeSTArray arr (fi ch fiAct) 1

loadSmp :: ByteString -> STArray s -> Integer -> Integer -> ST s ()
loadSmp fd arr ch sn =
    let off = smpOffset fd (sn - 1)
        sl  = smpLen fd off
        lb  = smpLoopBegin fd off
        le  = smpLoopEnd fd off
        c5  = smpC5Freq fd off
        dp  = smpDataPtr fd off
        dv  = smpDefaultVol fd off
        gv  = smpGlobalVol fd off
        fl  = smpFlags fd off
        hl  = if smpHasLoop fl then 1 else 0
        b16 = if smpIs16Bit fl then 1 else 0
    in do
        writeSTArray arr (fi ch fiSmp) sn
        writeSTArray arr (fi ch fiLen) sl
        writeSTArray arr (fi ch fiLpS) lb
        writeSTArray arr (fi ch fiLpE) le
        writeSTArray arr (fi ch fiLp) hl
        writeSTArray arr (fi ch fiDPtr) dp
        writeSTArray arr (fi ch fiC5) c5
        writeSTArray arr (fi ch fiVol) dv
        writeSTArray arr (fi ch fi16) b16
        writeSTArray arr (fi ch fiGVl) gv

-- ========== Mixing (ST monad — same STArray as decoding) ==========

mixTick :: ByteString -> STArray s -> Integer -> Integer
    -> [ByteString] -> ST s [ByteString]
mixTick fd arr spt numCh chunks = do
    pcm <- mixFrames fd arr spt numCh []
    return (pcm : chunks)

mixFrames :: ByteString -> STArray s -> Integer -> Integer
    -> [ByteString] -> ST s ByteString
mixFrames fd arr 0 _ acc = return (bsConcatList (reverse acc))
mixFrames fd arr n numCh acc = do
    frame <- mixFrame fd arr numCh 0 0 0
    let l   = fst frame
    let r   = snd frame
    let ml  = (l * 48) `div` (128 * 3)
    let mr  = (r * 48) `div` (128 * 3)
    let pcm = bsConcat (bsPutI16LE (clamp (0 - 32768) 32767 ml)) (bsPutI16LE (clamp (0 - 32768) 32767 mr))
    mixFrames fd arr (n - 1) numCh (pcm : acc)

mixFrame :: ByteString -> STArray s -> Integer -> Integer
    -> Integer -> Integer -> ST s (Integer, Integer)
mixFrame fd arr numCh ch la ra =
    if ch >= numCh
    then return (la, ra)
    else do
        act <- readSTArray arr (fi ch fiAct)
        if act == 0
        then mixFrame fd arr numCh (ch + 1) la ra
        else do
            pos  <- readSTArray arr (fi ch fiPos)
            sl   <- readSTArray arr (fi ch fiLen)
            dp   <- readSTArray arr (fi ch fiDPtr)
            vol  <- readSTArray arr (fi ch fiVol)
            pan  <- readSTArray arr (fi ch fiPan)
            is16 <- readSTArray arr (fi ch fi16)
            gvl  <- readSTArray arr (fi ch fiGVl)
            let smpPos = pos `div` 256
            let smp = if smpPos < sl then readSmp fd dp smpPos (is16 == 1) else 0
            let sv  = if is16 == 1 then (smp * vol * gvl * 128) `div` (64 * 64 * 128) else (smp * vol * gvl * 128 * 256) `div` (64 * 64 * 128)
            let nl = la + (sv * (64 - pan)) `div` 64
            let nr = ra + (sv * pan) `div` 64
            advPos arr ch
            mixFrame fd arr numCh (ch + 1) nl nr

advPos :: STArray s -> Integer -> ST s ()
advPos arr ch = do
    pos <- readSTArray arr (fi ch fiPos)
    inc <- readSTArray arr (fi ch fiInc)
    sl  <- readSTArray arr (fi ch fiLen)
    hl  <- readSTArray arr (fi ch fiLp)
    ls  <- readSTArray arr (fi ch fiLpS)
    le  <- readSTArray arr (fi ch fiLpE)
    let nPos = pos + inc
    let slFP = sl * 256
    let lsFP = ls * 256
    let leFP = le * 256
    let fPos = if hl == 1 && nPos >= leFP && leFP > lsFP then lsFP + ((nPos - lsFP) `mod` (leFP - lsFP)) else nPos
    writeSTArray arr (fi ch fiPos) fPos
    if hl == 0 && nPos >= slFP
    then writeSTArray arr (fi ch fiAct) 0
    else return ()

-- ========== Inner loop: decode + mix one pattern (pure, inside runST) ==========

doTicks :: ByteString -> STArray s -> Integer -> Integer -> Integer
    -> [ByteString] -> ST s [ByteString]
doTicks fd arr speed spt numCh chunks =
    doTickLoop fd arr speed spt numCh 0 chunks

doTickLoop :: ByteString -> STArray s -> Integer -> Integer -> Integer
    -> Integer -> [ByteString] -> ST s [ByteString]
doTickLoop fd arr speed spt numCh tick chunks =
    if tick >= speed
    then return chunks
    else do
        chunks2 <- mixTick fd arr spt numCh chunks
        doTickLoop fd arr speed spt numCh (tick + 1) chunks2

doRows :: ByteString -> STArray s -> ByteString -> ByteString
    -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Integer
    -> [ByteString] -> ST s ([ByteString], [Integer])
doRows fd arr masks lv dataOff row numRows speed tempo numCh numSmp chunks =
    if row >= numRows
    then do
        st2 <- stArrayToList arr
        return (chunks, st2)
    else do
        rr <- decodeRow fd dataOff arr masks lv numCh numSmp
        let masks2  = fst rr
        let lv2     = fst (snd rr)
        let nextOff = snd (snd rr)
        let spt     = (outRate * 60) `div` (tempo * 24)
        chunks2 <- doTicks fd arr speed spt numCh chunks
        doRows fd arr masks2 lv2 nextOff (row + 1) numRows speed tempo numCh numSmp chunks2

-- Process one pattern: enter runST, decode all rows + mix, return PCM chunks + updated state
processPattern :: ByteString -> [Integer] -> Integer -> Integer
    -> Integer -> Integer -> Integer -> Integer
    -> ([ByteString], [Integer])
processPattern fd st pOff nRows speed tempo numCh numSmp =
    let masks = bsReplicate 64 0
        lv    = bsReplicate 256 0
    in runST (do
        arr <- newSTArrayFromList st
        doRows fd arr masks lv (pOff + 8) 0 nRows speed tempo numCh numSmp [])

-- ========== Playback Loop (LuaIO for output callback) ==========

emitChunks :: (ByteString -> LuaIO s ()) -> [ByteString] -> LuaIO s ()
emitChunks sw [] = return ()
emitChunks sw (c:cs) = sw c >> emitChunks sw cs

findNextPos :: [Integer] -> Integer -> Integer -> Maybe Integer
findNextPos playedPositions maxPosition n
    | n < maxPosition = if contains n playedPositions
                        then findNextPos playedPositions maxPosition (n + 1)
                        else Just n
    | otherwise       = Nothing

handleEnd :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer]
    -> Integer -> Integer -> Integer
    -> Integer -> Integer -> Bool -> [Integer] -> LuaIO s ()
handleEnd fd sw st ordNum speed tempo numCh numSmp noLoop playedPositions =
    if noLoop
    then case findNextPos playedPositions ordNum 0 of
        Nothing -> return ()
        Just newPos -> doOrders fd sw st newPos ordNum speed tempo numCh numSmp noLoop (newPos:playedPositions)
    else return ()

doOrders :: ByteString -> (ByteString -> LuaIO s ()) -> [Integer]
    -> Integer -> Integer -> Integer -> Integer
    -> Integer -> Integer -> Bool -> [Integer] -> LuaIO s ()
doOrders fd sw st idx ordNum speed tempo numCh numSmp noLoop playedPositions =
    if idx >= ordNum
    then return ()
    else let pat = getOrder fd idx
         in if pat == 254
            then doOrders fd sw st (idx + 1) ordNum speed tempo numCh numSmp noLoop (idx:playedPositions)
            else if pat == 255
            then handleEnd fd sw st ordNum speed tempo numCh numSmp noLoop playedPositions
            else let pOff  = patOffset fd pat
                     nRows = patRows fd pOff
                     result = processPattern fd st pOff nRows speed tempo numCh numSmp
                     chunks = fst result
                     st2    = snd result
                 in emitChunks sw (reverse chunks)
                        >> doOrders fd sw st2 (idx + 1) ordNum speed tempo numCh numSmp noLoop (idx:playedPositions)

-- Find IMPM magic to skip UMX/container headers.
-- Returns the offset of 'I' in 'IMPM', or 0 if the file starts with it.
findIMPM :: ByteString -> Integer -> Integer
findIMPM bs i =
    if i + 3 >= bsLength bs then 0
    else if bsIndex bs i == 73 && bsIndex bs (i + 1) == 77 && bsIndex bs (i + 2) == 80 && bsIndex bs (i + 3) == 77
    then i
    else findIMPM bs (i + 1)

export play :: (ByteString -> LuaIO s ()) -> ByteString -> Bool -> LuaIO s ()
play swallower fd noLoop =
    (liftIO $ putStrLn "Pure mata-ll Impulse Tracker decoder") >>
    let offset = findIMPM fd 0
        itData = if offset == 0 then fd else bsSub fd offset (bsLength fd - offset)
        numCh  = countActiveChans itData 0 0
        st     = initChans itData numCh 0
    in doOrders itData swallower st 0 (hdrOrdNum itData) (hdrSpeed itData) (hdrTempo itData) numCh (hdrSmpNum itData) noLoop []

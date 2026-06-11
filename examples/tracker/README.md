A proof of concept decoder for IT (Impulse Tracker) music files. It
can feed the decoded raw audio stream to sox for real time playback
(well, not so much real time yet because it is as of yet still very
slow) or alternatively write them to a raw audio stream on disk which
you can later play back with sox.

What is the ImpulseTracker format? It is the score and instruments
combined in one file. Though they are usually referred to as samples
or sound fonts, not instruments; in fact, you could consider them a
superset of instruments.

The ImpulseTracker format was used in the Deus Ex (1) and Unreal (1)
games, amongst others.

Main goal - create mobile app to take a quick photoas and quickly add short description and audio.
The app should work as a photo galery for good memories.

Design
- each photo - is a card. on which we have photo itself and some date below the photo.
- we always display the date
- also optional text (if added)
- optional audio (if added)
- optional icon of geo location (if location is enabled)

Basically each card looks like polaroid photo, but with bigger bottom empty part, on which we can have some contene described above


Desired functionality
- In the app we have button - take a photo - this should launch device camera to take a photo. we always take photo in 1x1 aspect ration. and automatically compress them to 1 mb
- Once photo is taken - we can add a short text and / or audio
- in order to add audio - we hold the mic icon. while it is hold - we record voice of the user
- Then we press Done button - and the card is saved
- This all is stored on device. probably in the app DB. Because Photos taken in the app should not appear in the device galery right away. But we need to have functionality to make photos available in galery, probably cia manual export
- We can import photos from galery - tne we automatically get date of the photo from file metadata
- cards can be organazied in collections. Like Italy trip, Christmass, Family dinner 2023 etc. But for start it should be "Defaul" collection
- The whole collection can be exportet. An I want each card to have image, text, audio in one file. I am not sure what is the best way. maybe just archive each card data into one arhive and set some custom extension. And exported collection would be just one archive with a list of card archives inside. but may be there is a better way.


Technologies
- I think Flutter should be good. I compared it with react native and didn't find any advantage of react native for this idea


For Later
- we will have backend to support cloud storage, share and view. Mobile apps will be able to upload data in cloud and share specific cards and collections with other users
- we will have web-app to access backend
- Auth (email and 1 time password code for beginning)
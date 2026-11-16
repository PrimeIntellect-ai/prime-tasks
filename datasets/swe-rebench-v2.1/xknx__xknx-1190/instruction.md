Cover update callback stops in some special case
Hello!

My intention is to use `device_updated_cb` callback for Cover to process some logic during its movement etc..
I faced the problem when callback stops working in some special case, for example:

Pretend the blind initial position is 0% and we need to move it to 90%
1) start moving the blind to some position `await cover.set_position(90)`
2) send Stop during movement `cover.stop()`
3) then continue to move it to the previously given position `await cover.set_position(90)`
Here the `device_updated_cb` stops
4) if then or instead to send the blind to any other position but except 90%, the callback gets back to work, for example, sending to any of 0-89 or 91-100% .

Not sure if I'm doing something not correctly.
Here is the reduced example:

`
async def cover_update_cb(cover: Cover):
    print('Something inside cover update callback')

cover: Cover = None

async def test():
    global cover
    await asyncio.sleep(1)
    await cover.set_position(90)
    await asyncio.sleep(4)
    print('STOP command')
    await cover.stop()
    await asyncio.sleep(2)
    print(f'Continue to move to 90')
    await cover.set_position(90)
    #  here cover_update_cb stops. If instead set any different position from a position that the blind started moving from at the beginning (in our case 90) then callback will work.

async def main():
    global cover
    xknx = XKNX(daemon_mode=True)

    cover = Cover(
        xknx,
        'Cover',
        group_address_stop = "1/1/2",
        group_address_position = "1/1/3",
        group_address_position_state = "1/1/4",
        device_updated_cb=cover_update_cb
    )

    loop = asyncio.get_running_loop()
    loop.create_task(test())

    await xknx.start()
    await xknx.stop()

asyncio.run(main())

`

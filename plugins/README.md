## plugins

Put patches inside an "app-patches" folder or "bootstrap-patches" folder inside a "play-store-patches" or "f-droid-patches" folder corresponding to the app type used, inside that folder to have them applied to the app or bootstraps, respectively, that are built when the `--plugin` argument is used.

### Examples

#### `gradle-project`

```bash
./build-termux.sh \
    --name com.logicodeum.ide \
    --type f-droid \
    --architectures aarch64,arm \
    --plugin gradle-project \
    --disable-bootstrap-second-stage \
    --disable-terminal \
    --disable-tasker \
    --disable-float \
    --disable-widget \
    --disable-api \
    --disable-boot \
    --disable-styling \
    --disable-gui \
    --disable-x11
```

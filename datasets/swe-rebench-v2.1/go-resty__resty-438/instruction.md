Upload empty file get "EOF" error
```golang
	result := &app.AFSRetInfo{}
	url := fmt.Sprintf("http://%s/v1/game_volume/upload_file", u.Host)

	srcBytes, err := ioutil.ReadFile(u.SrcPath)
	if err != nil {
		s := fmt.Sprintf("UploadFileInfo.Do: ReadFile faild, url[%s] u[%+v] err[%v]", url, u, err)
		vlog.Error(s)
		return errors.New(s)
	}

	req := client.R().SetFormData(map[string]string{"file_path": u.DestPath}).
		SetFileReader("file", filepath.Base(u.SrcPath), bytes.NewReader(srcBytes)).
		SetContentLength(true).
		SetResult(result)
```

upload empty file error

```shell
ERROR	AStorage.UploadHandle: UpLoadFileList faild, err[UploadFileInfo.Do: faild, url[http://10.86.22.118:48885/v1/game_volume/upload_file] u[&{Host:10.86.22.118:48885 SrcPath:/Users/haibei/vrviuworks/code/be_gsm_tester/data/snapshot/area_user_game_data/2_642_1/data/Shooty Skies/moregames/kong DestPath:/data/data/test/kongfile/kong}] err[EOF]]	{"LAPP": "vm_game_planner", "LPID": 21068, "LFILE": "v1/android.go", "LLINE": 44, "LIP": ""}
```

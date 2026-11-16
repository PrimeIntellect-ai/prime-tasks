ListMembers: vars duplicated on subsequent pages
There is an issue with the mailing list `ListMembers` method where vars from a previous page will be copied to the next page if vars aren't set on that page.

See this example:

```go
func main() {
	ctx := context.Background()
	listAddr := "test@mydomain.com"

	client := mailgun.NewMailgun("mydomain.com", "my_key")

	for i := 0; i < 200; i++ {
		memberAddr := fmt.Sprintf("%03d@example.com", i)

		var vars map[string]interface{}
		if i == 5 {
			vars = map[string]interface{}{"has": "vars"}
		}

		err := client.CreateMember(ctx, false, listAddr, mailgun.Member{
			Address: memberAddr,
			Vars:    vars,
		})
		if err != nil {
			panic(err)
		}
	}

	it := client.ListMembers(listAddr, nil)

	var members []mailgun.Member
	for it.Next(ctx, &members) {
		for _, m := range members {
			fmt.Println(m.Address, m.Vars)
		}
	}
	if err := it.Err(); err != nil {
		panic(err)
	}
}
```

You would expect this code to only return vars for `005@example.com`, but it also returns vars for `105@example.com` because it's in the same position on the next page returned by the iterator.

Output here:

```
000@example.com map[]
001@example.com map[]
002@example.com map[]
003@example.com map[]
004@example.com map[]
005@example.com map[has:vars]
006@example.com map[]
007@example.com map[]
008@example.com map[]
009@example.com map[]
010@example.com map[]
011@example.com map[]
012@example.com map[]
013@example.com map[]
014@example.com map[]
015@example.com map[]
016@example.com map[]
017@example.com map[]
018@example.com map[]
019@example.com map[]
020@example.com map[]
021@example.com map[]
022@example.com map[]
023@example.com map[]
024@example.com map[]
025@example.com map[]
026@example.com map[]
027@example.com map[]
028@example.com map[]
029@example.com map[]
030@example.com map[]
031@example.com map[]
032@example.com map[]
033@example.com map[]
034@example.com map[]
035@example.com map[]
036@example.com map[]
037@example.com map[]
038@example.com map[]
039@example.com map[]
040@example.com map[]
041@example.com map[]
042@example.com map[]
043@example.com map[]
044@example.com map[]
045@example.com map[]
046@example.com map[]
047@example.com map[]
048@example.com map[]
049@example.com map[]
050@example.com map[]
051@example.com map[]
052@example.com map[]
053@example.com map[]
054@example.com map[]
055@example.com map[]
056@example.com map[]
057@example.com map[]
058@example.com map[]
059@example.com map[]
060@example.com map[]
061@example.com map[]
062@example.com map[]
063@example.com map[]
064@example.com map[]
065@example.com map[]
066@example.com map[]
067@example.com map[]
068@example.com map[]
069@example.com map[]
070@example.com map[]
071@example.com map[]
072@example.com map[]
073@example.com map[]
074@example.com map[]
075@example.com map[]
076@example.com map[]
077@example.com map[]
078@example.com map[]
079@example.com map[]
080@example.com map[]
081@example.com map[]
082@example.com map[]
083@example.com map[]
084@example.com map[]
085@example.com map[]
086@example.com map[]
087@example.com map[]
088@example.com map[]
089@example.com map[]
090@example.com map[]
091@example.com map[]
092@example.com map[]
093@example.com map[]
094@example.com map[]
095@example.com map[]
096@example.com map[]
097@example.com map[]
098@example.com map[]
099@example.com map[]
100@example.com map[]
101@example.com map[]
102@example.com map[]
103@example.com map[]
104@example.com map[]
105@example.com map[has:vars]
106@example.com map[]
107@example.com map[]
108@example.com map[]
109@example.com map[]
110@example.com map[]
111@example.com map[]
112@example.com map[]
113@example.com map[]
114@example.com map[]
115@example.com map[]
116@example.com map[]
117@example.com map[]
118@example.com map[]
119@example.com map[]
120@example.com map[]
121@example.com map[]
122@example.com map[]
123@example.com map[]
124@example.com map[]
125@example.com map[]
126@example.com map[]
127@example.com map[]
128@example.com map[]
129@example.com map[]
130@example.com map[]
131@example.com map[]
132@example.com map[]
133@example.com map[]
134@example.com map[]
135@example.com map[]
136@example.com map[]
137@example.com map[]
138@example.com map[]
139@example.com map[]
140@example.com map[]
141@example.com map[]
142@example.com map[]
143@example.com map[]
144@example.com map[]
145@example.com map[]
146@example.com map[]
147@example.com map[]
148@example.com map[]
149@example.com map[]
150@example.com map[]
151@example.com map[]
152@example.com map[]
153@example.com map[]
154@example.com map[]
155@example.com map[]
156@example.com map[]
157@example.com map[]
158@example.com map[]
159@example.com map[]
160@example.com map[]
161@example.com map[]
162@example.com map[]
163@example.com map[]
164@example.com map[]
165@example.com map[]
166@example.com map[]
167@example.com map[]
168@example.com map[]
169@example.com map[]
170@example.com map[]
171@example.com map[]
172@example.com map[]
173@example.com map[]
174@example.com map[]
175@example.com map[]
176@example.com map[]
177@example.com map[]
178@example.com map[]
179@example.com map[]
180@example.com map[]
181@example.com map[]
182@example.com map[]
183@example.com map[]
184@example.com map[]
185@example.com map[]
186@example.com map[]
187@example.com map[]
188@example.com map[]
189@example.com map[]
190@example.com map[]
191@example.com map[]
192@example.com map[]
193@example.com map[]
194@example.com map[]
195@example.com map[]
196@example.com map[]
197@example.com map[]
198@example.com map[]
199@example.com map[]
```

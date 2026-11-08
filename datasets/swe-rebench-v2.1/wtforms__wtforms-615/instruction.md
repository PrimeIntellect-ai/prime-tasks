DataRequired and InputRequired do not add required attribute to RadioField objects
  When adding a `DataRequired` or `InputRequired` validator to a `RadioField`, the `required` attribute of the `input` tag.

Here's the function I wrote that reveals the problem:

```python
    @bp.route('/<string:slug>/survey', methods=['GET', 'POST'])
    def survey(slug):
        survey = Survey.query.filter_by(slug=slug).first_or_404()
        questions = survey.questions
        for question in questions:
            if question.category == 'word':
                field = StringField(question.question, validators=[InputRequired()])
            elif question.category == 'likert':
                choices = [('1', 'Strongly Agree'),
                           ('2', 'Agree'),
                           ('3', 'Neutral'),
                           ('4', 'Disagree'),
                           ('5', 'Strongly Disagree')]
                field = RadioField(question.question, choices=choices, validators=[InputRequired()])
            setattr(FlaskForm, str(question.id), field)
        setattr(FlaskForm, 'submit', SubmitField('Submit'))
        form = FlaskForm()
        if form.validate_on_submit():
            response = Response(survey=survey)
            db.session.add(response)
            for question in questions:
                answer = Answer(question=question, response=response)
                field = getattr(form, str(question.id))
                if question.category == 'word':
                    answer.answer = field.data
                elif question.category == 'likert':
                    choices = {'1': 'Strongly Agree',
                               '2': 'Agree',
                               '3': 'Neutral',
                               '4': 'Disagree',
                               '5': 'Strongly Disagree'}
                    answer.answer = choices[field.data]
                db.session.add(answer)
            db.session.commit()
            with open('app/static/ty.txt', 'r') as f:
                ty = [x.strip() for x in f.readlines()]
            return render_template('ty.html', ty=ty)
        return render_template('survey.html', form=form, questions=questions)
```

I understand there might be other issues with the above (such as me being informed I should subclass FlaskForm).

The above function gives the following `input` tag for a `StringField`:

```html
    <input class="form-control" id="4" name="4" required="" type="text" value="">
```

This is the `input` tag for a `RadioField`:

```html
    <input id="1-0" name="1" type="radio" value="1">
```

While in the browser's debugger, if I edit the above to `<input id="1-0" name="1" type="radio" value="1" required="">`, the radio button requires a selection.

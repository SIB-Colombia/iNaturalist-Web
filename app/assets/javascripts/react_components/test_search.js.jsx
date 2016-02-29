var React;

var ObservationSearch = React.createClass({
  getInitialState: function( ) {
    return { observations: [ ] };
  },
  componentDidMount: function( ) {
    this.loadObservations( );
  },
  loadObservations: function( search ) {
    if( !search ) { return; }
    $.ajax({
      url: `http://api.inaturalist.org/v1/observations?q=${ search }&search_on=name&per_page=50`,
      dataType: 'json',
      cache: false,
      success: function( data ) {
        this.setState({ observations: _.map( data.results, function( r ) {
          return new iNatModels.Observation( r );
        })});
      }.bind( this ),
      error: function( xhr, status, err ) {
        console.error( this.props, status, err.toString( ) );
      }.bind( this )
    });
  },
  render: function( ) {
    return (
      <div>
        <h1>Observations</h1>
        <SearchForm onSearchSubmit={ this.loadObservations } />
        <ObservationList observations={ this.state.observations } />
      </div>
    );
  }
});

var SearchForm = React.createClass({
  propTypes: {
    onSearchSubmit: React.PropTypes.func
  },
  getInitialState: function( ) {
    return { searchTerm: null, onSearchSubmit: undefined };
  },
  handleChange: function( e ) {
    this.setState({ searchTerm: e.target.value });
  },
  handleSubmit: function( e ) {
    e.preventDefault( );
    this.props.onSearchSubmit( this.state.searchTerm );
  },
  render: function( ) {
    return (
      <form className="searchForm" onSubmit={ this.handleSubmit }>
        <input
          type="text"
          placeholder="Search for taxa"
          value={ this.state.searchTerm }
          onChange={ this.handleChange }
        />
        <input type="submit" value="Post" />
      </form>
    );
  }
});

var ObservationList = React.createClass({
  propTypes: {
    observations: React.PropTypes.array.isRequired
  },
  getInitialState: function( ) {
    return { observations: [ ] };
  },
  render: function( ) {
    var that = this;
    var observationNodes = this.props.observations.map( function( observation ) {
      return (
        <Observation data={ observation } key={ observation.id } />
      );
    });
    return (
      <div className="observationList">
        {observationNodes}
      </div>
    );
  }
});

var Observation = React.createClass({
  propTypes: {
    data: React.PropTypes.object.isRequired
  },
  render: function() {
    var image;
    if( this.props.data.photo( ) ) {
      image = <img src={ this.props.data.photo( ) } />;
    }
    var name = this.props.data.species_guess;
    if( !name && this.props.data.taxon ) {
      name = this.props.data.taxon.name;
    }
    if( !name ) {
      name = "Unknown"
    }
    return (
      <div className="observation">
        <div className="name">
          <a href={ `/observations/${ this.props.data.id }` }>
            { name }
          </a>
        </div>
        <div className="image">
          {image}
        </div>
        <CommentForm { ...this.props } onCommentSubmit={ this.handleCommentSubmit } />
      </div>
    );
  }
});

var CommentForm = React.createClass({
  propTypes: {
    data: React.PropTypes.object.isRequired,
    onCommentSubmit: React.PropTypes.func
  },
  getInitialState: function( ) {
    return {
      body: undefined,
      placeholder: "Say something...",
      csrf_param: $( "meta[name='csrf-param']" ).attr( "content" ),
      csrf_token: $( "meta[name='csrf-token']" ).attr( "content" )
    };
  },
  handleChange: function( e ) {
    this.setState({ body: e.target.value });
  },
  handleSubmit: function( e ) {
    e.preventDefault( );
    var body = this.state.body.trim( );
    if( !body ) { return; }
    if( !CURRENT_USER ) { return; }
    $("textarea[name='comment[body]']").val('');
    this.setState({ body: undefined, placeholder: "Submitting..." });
    var postData = {
      "comment[body]": body,
      "comment[parent_id]": this.props.data.id,
      "comment[parent_type]": "Observation",
      "comment[user_id]":  CURRENT_USER.id
    };
    postData[ this.state.csrf_param ] = this.state.csrf_token;
    $.ajax({
      type: "POST",
      url: "/comments",
      data: postData,
      dataType: "html",
      success: function( data ) {
        $("textarea[name='comment[body]']").val('');
        this.setState({ body: undefined, placeholder: "You said it!" });
      }.bind( this ),
      error: function( xhr, status, err ) {
        $("textarea[name='comment[body]']").val('');
        this.setState({ body: undefined, placeholder: "There was a problem" });
      }.bind( this )
    });
  },
  render: function( ) {
    return (
      <form className="new_comment" onSubmit={ this.handleSubmit }>
        <div className="stacked">
          <textarea
            name="comment[body]"
            className="form-control"
            placeholder={ this.state.placeholder }
            value={ this.state.body }
            onChange={ this.handleChange }
          />
        </div>
        <div className="buttonrow">
          <input className="default button" type="submit" value="Save Comment" />
        </div>
      </form>
    );
  }
});


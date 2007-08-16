
  <div id="loginbox">
    <form action="${location}login" name="login" id="loginbox-form" method="post" enctype="application/x-www-form-urlencoded"> 
    <h1 class="loginbox">Login</h1>
    <span class="label">User:</span><br />
    <input type="text" name="username" class="field" /><br />
    <span class="label">Password:</span><br />
    <input type="password" name="password" class="field" /><br />
    <input type="submit" value="Login" name="button" class="button" />
    <div class="forgot-pw">
    <a href="${location}forgotpw">Forgotten your username or password?</a>
    </div>
    </form>
  </div>

